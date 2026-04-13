import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Inject,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import {
  RateLimit,
  RateLimitGuard,
} from '../../core/common/guards/rate-limit.guard';
import { CurrentUser } from '../../core/common/decorators/current-user.decorator';
import type { RequestUser } from '../../core/common/decorators/current-user.decorator';
import { AudioGateway } from '../gateway/audio.gateway';
import { TTS_PROVIDER } from '../ai/interfaces/tokens';
import type { ITtsProvider } from '../ai/interfaces';
import { DevicesService } from './devices.service';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateSettingsDto } from './dto/update-settings.dto';
import { VoicePreviewDto } from './dto/voice-preview.dto';

/** Sample phrase used for every voice preview. Short, punchy, Aksa-style. */
const PREVIEW_PHRASE = "Yo, I'm Aksa — Hendra's desk companion. Built different, for real.";

@Controller('devices')
@UseGuards(JwtAuthGuard, RateLimitGuard)
@RateLimit({ limit: 60, windowSeconds: 60, keyType: 'user' })
export class DevicesController {
  constructor(
    private readonly devicesService: DevicesService,
    private readonly gateway: AudioGateway,
    @Inject(TTS_PROVIDER) private readonly tts: ITtsProvider,
  ) {}

  @Post()
  create(@CurrentUser() user: RequestUser, @Body() dto: CreateDeviceDto) {
    return this.devicesService.create(user.userId, dto);
  }

  @Get()
  findAll(@CurrentUser() user: RequestUser) {
    return this.devicesService.findAllByUser(user.userId);
  }

  @Get(':id')
  findOne(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.findById(id, user.userId);
  }

  @Patch(':id/settings')
  async updateSettings(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Body() dto: UpdateSettingsDto,
  ) {
    const device = await this.devicesService.updateSettings(id, user.userId, dto);
    // Push only the changed keys to the ESP32 (not the entire settings blob)
    this.gateway.sendToDevice(id, 'config:update', dto);
    return device;
  }

  @Post('claim')
  claim(
    @CurrentUser() user: RequestUser,
    @Body() body: { deviceToken: string },
  ) {
    return this.devicesService.claimByToken(user.userId, body.deviceToken);
  }

  @Get(':id/stats')
  getStats(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.getStats(id, user.userId);
  }

  /** Generate a short TTS preview in MP3 format for in-app playback.
   *  Returns base64-encoded MP3 so the app can play it directly.
   *  Rate-limited to 10 calls/min per user — TTS isn't free. */
  @Post(':id/voice/preview')
  @RateLimit({ limit: 10, windowSeconds: 60, keyType: 'user' })
  async voicePreview(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Body() dto: VoicePreviewDto,
  ) {
    // Verify device ownership — throws NotFoundException/ForbiddenException if wrong
    await this.devicesService.findById(id, user.userId);

    const mp3Buffer = await this.tts.synthesize(dto.text ?? PREVIEW_PHRASE, {
      voice: dto.voice_preset,
      speed: dto.voice_speed,
      stability: dto.voice_stability,
      outputFormat: 'mp3_44100_128',
    });

    return {
      audio: mp3Buffer.toString('base64'),
      mimeType: 'audio/mpeg',
    };
  }

  /** Push a TTS voice preview to the device for on-device playback.
   *  Returns 200 { playing: true } if the device is online and accepted the
   *  audio, or 200 { playing: false } if it is offline / busy (so the app
   *  can fall back to local playback without treating it as an error). */
  @Post(':id/voice/preview/push')
  @RateLimit({ limit: 10, windowSeconds: 60, keyType: 'user' })
  async voicePreviewPush(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Body() dto: VoicePreviewDto,
  ) {
    await this.devicesService.findById(id, user.userId);

    const voiceOpts = {
      voice: dto.voice_preset,
      speed: dto.voice_speed,
      stability: dto.voice_stability,
    };
    const playing = await this.gateway.sendVoicePreviewToDevice(id, voiceOpts, dto.text);
    return { playing };
  }

  /** Signal an online device to reboot into BLE provisioning mode.
   *  Sends `device:provision` via WebSocket so the ESP32 sets the force-provision
   *  NVS flag and restarts — the app can then re-provision it over BLE.
   *  Returns 204 whether or not the device is currently online (the WS send is
   *  fire-and-forget; the app should guide the user through the offline path). */
  @Post(':id/provision')
  @HttpCode(HttpStatus.NO_CONTENT)
  async requestProvision(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    await this.devicesService.findById(id, user.userId);
    this.gateway.sendToDevice(id, 'device:provision', {});
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.remove(id, user.userId);
  }
}
