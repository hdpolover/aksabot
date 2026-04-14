import {
  ConflictException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  forwardRef,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { createHash } from 'crypto';
import { readFile, unlink } from 'fs/promises';
import { existsSync } from 'fs';
import { join } from 'path';
import type Redis from 'ioredis';
import { FirmwareRelease } from '../../core/database/entities';
import { REDIS_CLIENT } from '../../core/cache/redis.provider';
import { DevicesService } from '../devices/devices.service';
import { AudioGateway } from '../gateway/audio.gateway';

export interface OtaStatus {
  state: 'idle' | 'triggered' | 'in_progress' | 'complete' | 'error';
  progress: number;
  phase?: string;
  error?: string;
  version?: string;
}

const FIRMWARE_DIR = join(process.cwd(), 'uploads', 'firmware');
const OTA_STATUS_TTL = 3600; // 1 hour

@Injectable()
export class FirmwareService {
  private readonly logger = new Logger(FirmwareService.name);

  constructor(
    @InjectRepository(FirmwareRelease)
    private readonly repo: Repository<FirmwareRelease>,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
    private readonly devicesService: DevicesService,
    @Inject(forwardRef(() => AudioGateway))
    private readonly gateway: AudioGateway,
  ) {}

  // ── Firmware releases ──────────────────────────────────────────

  async upload(
    file: Express.Multer.File,
    version: string,
    changelog?: string,
  ): Promise<FirmwareRelease> {
    const existing = await this.repo.findOne({ where: { version } });
    if (existing) {
      // Clean up the uploaded file before throwing
      await unlink(file.path).catch(() => {});
      throw new ConflictException(`Firmware version ${version} already exists`);
    }

    const sha256 = createHash('sha256')
      .update(await readFile(file.path))
      .digest('hex');

    const release = this.repo.create({
      version,
      filename: file.filename,
      sha256,
      size: file.size,
      changelog: changelog ?? null,
    });

    const saved = await this.repo.save(release);
    this.logger.log(`Firmware ${version} uploaded (${file.size} bytes, sha256=${sha256.slice(0, 16)}...)`);
    return saved;
  }

  findAll(): Promise<FirmwareRelease[]> {
    return this.repo.find({ order: { createdAt: 'DESC' } });
  }

  async findLatest(): Promise<FirmwareRelease | null> {
    return this.repo.findOne({ order: { createdAt: 'DESC' }, where: {} });
  }

  async findById(id: string): Promise<FirmwareRelease> {
    const release = await this.repo.findOne({ where: { id } });
    if (!release) throw new NotFoundException(`Firmware release ${id} not found`);
    return release;
  }

  getFilePath(filename: string): string {
    return join(FIRMWARE_DIR, filename);
  }

  // ── OTA operations ─────────────────────────────────────────────

  async triggerOta(
    deviceId: string,
    userId: string,
    releaseId?: string,
  ): Promise<{ triggered: boolean; version: string }> {
    // Validate device ownership — throws ForbiddenException/NotFoundException if wrong
    await this.devicesService.findById(deviceId, userId);

    const release = releaseId
      ? await this.findById(releaseId)
      : await this.findLatest();

    if (!release) {
      throw new NotFoundException('No firmware releases available. Upload a .bin first.');
    }

    const baseUrl = process.env.BACKEND_URL ?? 'http://localhost:4280';
    const downloadUrl = `${baseUrl}/firmware/${release.id}/download`;

    // Store initial status — app can poll this while device downloads
    await this.setOtaStatus(deviceId, {
      state: 'triggered',
      progress: 0,
      version: release.version,
    });

    // Send OTA start event to device via WebSocket
    this.gateway.sendToDevice(deviceId, 'ota:start', {
      url: downloadUrl,
      sha256: release.sha256,
      version: release.version,
    });

    this.logger.log(`OTA triggered: device=${deviceId} version=${release.version}`);
    return { triggered: true, version: release.version };
  }

  async getOtaStatus(deviceId: string, userId: string): Promise<OtaStatus> {
    await this.devicesService.findById(deviceId, userId);
    const raw = await this.redis.get(`ota:status:${deviceId}`);
    if (!raw) return { state: 'idle', progress: 0 };
    try {
      return JSON.parse(raw) as OtaStatus;
    } catch {
      return { state: 'idle', progress: 0 };
    }
  }

  async setOtaStatus(deviceId: string, status: OtaStatus): Promise<void> {
    await this.redis.set(
      `ota:status:${deviceId}`,
      JSON.stringify(status),
      'EX',
      OTA_STATUS_TTL,
    );
  }

  /** Called by the gateway when the device sends ota:progress or ota:complete. */
  async onOtaProgress(deviceId: string, data: { percent?: number; phase?: string }): Promise<void> {
    await this.setOtaStatus(deviceId, {
      state: 'in_progress',
      progress: data.percent ?? 0,
      phase: data.phase,
    });
  }

  async onOtaComplete(
    deviceId: string,
    data: { success?: boolean; error?: string },
  ): Promise<void> {
    if (data.success) {
      await this.setOtaStatus(deviceId, {
        state: 'complete',
        progress: 100,
      });
      this.logger.log(`OTA complete for device ${deviceId}`);
    } else {
      await this.setOtaStatus(deviceId, {
        state: 'error',
        progress: 0,
        error: data.error ?? 'Unknown error',
      });
      this.logger.warn(`OTA failed for device ${deviceId}: ${data.error}`);
    }
  }

  /** Returns the local filesystem path and whether the file exists. */
  resolveFirmwarePath(filename: string): { path: string; exists: boolean } {
    const path = this.getFilePath(filename);
    return { path, exists: existsSync(path) };
  }
}
