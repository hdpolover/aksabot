import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Post,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { extname, join } from 'path';
import { existsSync, createReadStream, mkdirSync } from 'fs';
import { randomUUID } from 'crypto';
import type { Response } from 'express';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import {
  RateLimit,
  RateLimitGuard,
} from '../../core/common/guards/rate-limit.guard';
import { CurrentUser } from '../../core/common/decorators/current-user.decorator';
import type { RequestUser } from '../../core/common/decorators/current-user.decorator';
import { FirmwareService } from './firmware.service';

const FIRMWARE_DIR = join(process.cwd(), 'uploads', 'firmware');

@Controller()
export class FirmwareController {
  constructor(private readonly firmwareService: FirmwareService) {}

  // ── Firmware releases ─────────────────────────────────────────

  /** Upload a new firmware .bin release. */
  @Post('firmware')
  @UseGuards(JwtAuthGuard, RateLimitGuard)
  @RateLimit({ limit: 10, windowSeconds: 60, keyType: 'user' })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req, _file, cb) => {
          mkdirSync(FIRMWARE_DIR, { recursive: true });
          cb(null, FIRMWARE_DIR);
        },
        filename: (_req, _file, cb) => {
          cb(null, `${randomUUID()}.bin`);
        },
      }),
      limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB max
      fileFilter: (_req, file, cb) => {
        const ok = extname(file.originalname).toLowerCase() === '.bin' || file.mimetype === 'application/octet-stream';
        cb(null, ok);
      },
    }),
  )
  async uploadFirmware(
    @UploadedFile() file: Express.Multer.File,
    @Body('version') version: string,
    @Body('changelog') changelog?: string,
  ) {
    if (!file) {
      throw new NotFoundException('No .bin file provided');
    }
    if (!version) {
      throw new NotFoundException('version is required (e.g. "1.2.0")');
    }
    return this.firmwareService.upload(file, version, changelog);
  }

  /** List all firmware releases, newest first. */
  @Get('firmware')
  @UseGuards(JwtAuthGuard, RateLimitGuard)
  @RateLimit({ limit: 60, windowSeconds: 60, keyType: 'user' })
  findAll() {
    return this.firmwareService.findAll();
  }

  /** Get the most recent firmware release. */
  @Get('firmware/latest')
  @UseGuards(JwtAuthGuard, RateLimitGuard)
  @RateLimit({ limit: 60, windowSeconds: 60, keyType: 'user' })
  async findLatest() {
    const release = await this.firmwareService.findLatest();
    if (!release) throw new NotFoundException('No firmware releases available');
    return release;
  }

  /** Serve a firmware binary. No JWT required — UUID-based URL is unguessable.
   *  The ESP32 uses this URL directly to download the firmware. */
  @Get('firmware/:id/download')
  async downloadFirmware(
    @Param('id', ParseUUIDPipe) id: string,
    @Res() res: Response,
  ) {
    const release = await this.firmwareService.findById(id);
    const { path, exists } = this.firmwareService.resolveFirmwarePath(release.filename);

    if (!exists) {
      res.status(404).json({ message: 'Firmware file not found on server' });
      return;
    }

    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="firmware-${release.version}.bin"`);
    res.setHeader('Content-Length', release.size);
    res.setHeader('X-Firmware-Version', release.version);
    res.setHeader('X-Firmware-SHA256', release.sha256);
    res.setHeader('Cache-Control', 'no-store');
    createReadStream(path).pipe(res);
  }

  // ── Device OTA operations ─────────────────────────────────────

  /** Trigger an OTA update on the device.
   *  Optionally pass { releaseId } to target a specific release; omit to use latest. */
  @Post('devices/:deviceId/ota/trigger')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard, RateLimitGuard)
  @RateLimit({ limit: 5, windowSeconds: 60, keyType: 'user' })
  async triggerOta(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
    @CurrentUser() user: RequestUser,
    @Body() body: { releaseId?: string },
  ) {
    return this.firmwareService.triggerOta(deviceId, user.userId, body.releaseId);
  }

  /** Poll OTA progress for a device.
   *  Returns { state, progress, phase?, error?, version? }.
   *  State: 'idle' | 'triggered' | 'in_progress' | 'complete' | 'error' */
  @Get('devices/:deviceId/ota/status')
  @UseGuards(JwtAuthGuard, RateLimitGuard)
  @RateLimit({ limit: 120, windowSeconds: 60, keyType: 'user' }) // polling — allow 2/s
  async getOtaStatus(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.firmwareService.getOtaStatus(deviceId, user.userId);
  }
}
