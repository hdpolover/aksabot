import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
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
import { DevicesService } from './devices.service';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateSettingsDto } from './dto/update-settings.dto';

@Controller('devices')
@UseGuards(JwtAuthGuard, RateLimitGuard)
@RateLimit({ limit: 60, windowSeconds: 60, keyType: 'user' })
export class DevicesController {
  constructor(
    private readonly devicesService: DevicesService,
    private readonly gateway: AudioGateway,
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

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.remove(id, user.userId);
  }
}
