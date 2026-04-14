import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Inject,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import type { Request } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage, memoryStorage } from 'multer';
import { extname, join } from 'path';
import { existsSync, createReadStream, mkdirSync, unlink, statSync } from 'fs';
import { randomUUID } from 'crypto';
import type { Response } from 'express';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import {
  RateLimit,
  RateLimitGuard,
} from '../../core/common/guards/rate-limit.guard';
import { CurrentUser } from '../../core/common/decorators/current-user.decorator';
import { Public } from '../../core/common/decorators/public.decorator';
import type { RequestUser } from '../../core/common/decorators/current-user.decorator';
import { AudioGateway } from '../gateway/audio.gateway';
import { TTS_PROVIDER, AUDIO_CODEC } from '../ai/interfaces/tokens';
import type { ITtsProvider, IAudioCodec } from '../ai/interfaces';
import { DevicesService } from './devices.service';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateSettingsDto } from './dto/update-settings.dto';
import { VoicePreviewDto } from './dto/voice-preview.dto';

const UPLOADS_DIR = join(process.cwd(), 'uploads', 'device-images');
const IMAGE_TTL_MS = 5 * 60 * 1000; // 5 min — long enough for the ESP32 to download it

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
    @Inject(AUDIO_CODEC) private readonly codec: IAudioCodec,
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
    // Keep the in-memory session in sync for language changes
    this.gateway.onSettingsUpdated(id, dto);
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
      language: dto.language,
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
      language: dto.language,
      voice: dto.voice_preset,
      speed: dto.voice_speed,
      stability: dto.voice_stability,
    };
    const playing = await this.gateway.sendVoicePreviewToDevice(id, voiceOpts, dto.text);
    return { playing };
  }

  /** Temporarily override device volume without touching the DB or NVS permanently.
   *  Sends `config:update { volume }` directly to the device via WebSocket.
   *  The caller is responsible for restoring the original volume when done.
   *  Volume range: 0–100. Returns 204 regardless of online status. */
  @Post(':id/volume-override')
  @HttpCode(HttpStatus.NO_CONTENT)
  async volumeOverride(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Body() body: { volume: number },
  ) {
    await this.devicesService.findById(id, user.userId);
    const clamped = Math.max(0, Math.min(100, Math.round(body.volume ?? 80)));
    this.gateway.sendToDevice(id, 'config:update', { volume: clamped });
  }

  /** Accept a pre-recorded voice message (raw 16kHz/mono/16-bit PCM or WAV),
   *  encode it to Opus, and send it to the device for playback.
   *  WAV files are automatically stripped of their 44-byte header.
   *  Returns { playing: true } if the device was online, { playing: false } otherwise. */
  @Post(':id/voice-message')
  @RateLimit({ limit: 10, windowSeconds: 60, keyType: 'user' })
  @UseInterceptors(
    FileInterceptor('audio', {
      storage: memoryStorage(),
      limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB — ~5 min of 16kHz PCM
    }),
  )
  async voiceMessage(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @UploadedFile() file: Express.Multer.File,
  ) {
    await this.devicesService.findById(id, user.userId);

    if (!file) {
      throw new NotFoundException('No audio file provided');
    }

    // Strip WAV header if present — locate "data" chunk to get raw PCM
    let pcm = file.buffer;
    if (pcm.length > 44 && pcm.subarray(0, 4).toString('ascii') === 'RIFF') {
      const dataIdx = pcm.indexOf(Buffer.from('data'));
      pcm = dataIdx !== -1 && dataIdx + 8 <= pcm.length
        ? pcm.subarray(dataIdx + 8)  // skip "data" marker + 4-byte chunk size
        : pcm.subarray(44);          // fallback: standard 44-byte header
    }

    const framedOpus = this.codec.encode(pcm);
    const playing = await this.gateway.sendVoiceMessage(id, framedOpus);
    return { playing };
  }

  /** Report a presence event from the mobile app (reverse BLE scan flow).
   *  The app scans for the ESP32's BLE advertisement and calls this endpoint
   *  when the user arrives or leaves — triggering the same greeting/departure
   *  logic as if the ESP32 had detected the phone itself. */
  @Post(':id/presence')
  @HttpCode(HttpStatus.NO_CONTENT)
  async reportPresence(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Body() body: { event: 'arrived' | 'departed'; awayDurationSeconds?: number },
  ) {
    await this.devicesService.findById(id, user.userId);
    if (body.event === 'arrived') {
      await this.gateway.onPresenceArrived(id, {
        awayDurationSeconds: body.awayDurationSeconds ?? 0,
      });
    } else {
      this.gateway.onPresenceDeparted(id);
    }
  }

  /** Fetch the most recent log lines from the device.
   *  Sends `log:fetch` to the device, waits up to 3s for `log:data` response,
   *  caches it in Redis (5 min TTL), and returns the text.
   *  Returns { text: null, cached: false } if the device is offline or times out. */
  @Post(':id/logs/fetch')
  async fetchLogs(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    await this.devicesService.findById(id, user.userId);
    const offline = !this.gateway.isDeviceConnected(id);
    const result = await this.gateway.fetchDeviceLogs(id);
    if (!result) {
      return { text: null, bytes: 0, fetchedAt: null, offline };
    }
    return { ...result, offline: false };
  }

  /** Return the last cached log snapshot without triggering a new fetch.
   *  Useful for retrieving recently fetched logs without waiting again.
   *  Returns { text: null } if no cached data is available. */
  @Get(':id/logs')
  async getLogs(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    await this.devicesService.findById(id, user.userId);
    const result = await this.gateway.getCachedLogs(id);
    if (!result) {
      return { text: null, bytes: 0, fetchedAt: null };
    }
    return result;
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

  /** Factory reset: send WS event so the device erases NVS and reboots,
   *  then delete the device record from the backend.
   *  Fire-and-forget for the WS send (device may be offline). */
  @Post(':id/factory-reset')
  @HttpCode(HttpStatus.NO_CONTENT)
  async factoryReset(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    await this.devicesService.findById(id, user.userId);
    // Tell device to erase NVS + restart (best-effort; may be offline)
    this.gateway.sendToDevice(id, 'control:factory_reset', {});
    // Give the WS event a brief window to reach the device before we revoke its token
    await new Promise((resolve) => setTimeout(resolve, 500));
    await this.devicesService.remove(id, user.userId);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.remove(id, user.userId);
  }

  /** Accept an image upload from the app, save it to disk, push a WS
   *  `display:image` event so the device downloads and shows it.
   *  The file is auto-deleted after IMAGE_TTL_MS (5 min).
   *  Accepts JPEG, PNG, or BMP. Rate-limited to 10/min (images are large). */
  @Post(':id/push-image')
  @RateLimit({ limit: 10, windowSeconds: 60, keyType: 'user' })
  @UseInterceptors(
    FileInterceptor('image', {
      storage: diskStorage({
        destination: (_req, _file, cb) => {
          mkdirSync(UPLOADS_DIR, { recursive: true });
          cb(null, UPLOADS_DIR);
        },
        filename: (_req, file, cb) => {
          const ext = extname(file.originalname).toLowerCase() || '.jpg';
          cb(null, `${randomUUID()}${ext}`);
        },
      }),
      limits: { fileSize: 2 * 1024 * 1024 }, // 2 MB — matches firmware PSRAM budget
      fileFilter: (_req, file, cb) => {
        const allowed = ['image/jpeg', 'image/png', 'image/bmp'];
        cb(null, allowed.includes(file.mimetype));
      },
    }),
  )
  async pushImage(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @UploadedFile() file: Express.Multer.File,
    @Body('durationMs') durationMsRaw?: string,
  ) {
    await this.devicesService.findById(id, user.userId);

    if (!file) {
      throw new NotFoundException('No image file provided or unsupported format (use JPEG, PNG, or BMP)');
    }

    const durationMs = durationMsRaw ? parseInt(durationMsRaw, 10) : 10000;

    // Derive base URL from the incoming request so it works in every environment
    // without needing BACKEND_URL. Respects X-Forwarded-Proto/Host set by Traefik.
    const proto = (req.headers['x-forwarded-proto'] as string | undefined)?.split(',')[0].trim()
      ?? (req.secure ? 'https' : 'http');
    const host = (req.headers['x-forwarded-host'] as string | undefined)?.split(',')[0].trim()
      ?? req.headers.host
      ?? 'localhost:4280';
    const baseUrl = `${proto}://${host}`;
    const imageUrl = `${baseUrl}/devices/${id}/device-images/${file.filename}`;

    // Push to device — fire and forget (device may be offline; user sees image when it reconnects)
    this.gateway.sendToDevice(id, 'display:image', { url: imageUrl, durationMs });

    // Schedule file cleanup
    setTimeout(() => {
      unlink(file.path, (err) => {
        if (err && (err as NodeJS.ErrnoException).code !== 'ENOENT') {
          // Ignore "file not found" (already cleaned up), log other errors
          console.warn(`[PushImage] cleanup failed for ${file.filename}:`, err.message);
        }
      });
    }, IMAGE_TTL_MS);

    return { url: imageUrl, durationMs, filename: file.filename };
  }

  /** Serve a previously uploaded device image. No auth required — the UUID
   *  filename is unguessable and the file is deleted after 5 minutes. */
  @Public()
  @Get(':id/device-images/:filename')
  async serveDeviceImage(
    @Param('id', ParseUUIDPipe) _id: string,
    @Param('filename') filename: string,
    @Res() res: Response,
  ) {
    // Sanitise: only allow safe filenames (UUID + extension, no path traversal)
    if (!/^[\w-]+\.(jpg|jpeg|png|bmp)$/i.test(filename)) {
      res.status(400).json({ message: 'Invalid filename' });
      return;
    }

    const filePath = join(UPLOADS_DIR, filename);
    if (!existsSync(filePath)) {
      res.status(404).json({ message: 'Image not found or already expired' });
      return;
    }

    const ext = extname(filename).toLowerCase();
    const mimeMap: Record<string, string> = {
      '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
      '.png': 'image/png', '.bmp': 'image/bmp',
    };
    const { size } = statSync(filePath);
    res.setHeader('Content-Type', mimeMap[ext] ?? 'application/octet-stream');
    res.setHeader('Content-Length', size);
    res.setHeader('Cache-Control', 'no-store'); // don't cache expiring files
    createReadStream(filePath).pipe(res);
  }
}
