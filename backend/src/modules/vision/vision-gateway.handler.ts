import { Injectable, Logger } from '@nestjs/common';
import { VisionService } from './vision.service';
import { SessionManager } from '../gateway/session.manager';
import { DevicesService } from '../devices/devices.service';

export interface PendingEnrollment {
  userId: string;
  name: string;
  frames: Buffer[];
}

@Injectable()
export class VisionGatewayHandler {
  private readonly logger = new Logger(VisionGatewayHandler.name);
  private sendFn: ((deviceId: string, event: string, data: any) => void) | null = null;
  private pendingEnrollments = new Map<string, PendingEnrollment>();

  constructor(
    private readonly visionService: VisionService,
    private readonly sessions: SessionManager,
    private readonly devicesService: DevicesService,
  ) {}

  setSendFn(fn: (deviceId: string, event: string, data: any) => void) {
    this.sendFn = fn;
  }

  /** Called by AudioGateway when a vision:frame binary message arrives. */
  async handleFrame(cameraDeviceId: string, jpegBuffer: Buffer): Promise<void> {
    const device = await this.devicesService.findByIdInternal(cameraDeviceId);
    if (!device) return;

    const userId = device.userId;
    const pairedDeviceId = (device.settingsJson as any)?.pairedDeviceId as string | undefined;

    const embedding = await this.visionService.detectAndEmbed(jpegBuffer);
    if (!embedding) {
      if (pairedDeviceId) {
        this.sessions.setCurrentIdentity(pairedDeviceId, null);
      }
      return;
    }

    const identity = await this.visionService.findBestMatch(userId, embedding);
    this.logger.debug(
      `Face match: ${identity.unknown ? 'unknown' : identity.name} (conf=${identity.confidence.toFixed(2)})`,
    );

    if (pairedDeviceId) {
      this.sessions.setCurrentIdentity(pairedDeviceId, {
        name: identity.name,
        unknown: identity.unknown,
      });

      this.sendFn?.(pairedDeviceId, 'face:identity', {
        name: identity.name,
        confidence: identity.confidence,
        unknown: identity.unknown,
      });
    }
  }

  /** Called by AudioGateway when vision:enroll_frames arrives (8 frames from live capture). */
  async handleEnrollFrames(cameraDeviceId: string, jpegFrames: Buffer[]): Promise<void> {
    const pending = this.pendingEnrollments.get(cameraDeviceId);
    if (!pending) {
      this.logger.warn(`Received enroll frames for ${cameraDeviceId} but no pending enrollment`);
      return;
    }
    this.pendingEnrollments.delete(cameraDeviceId);

    try {
      const profile = await this.visionService.enroll(pending.userId, pending.name, jpegFrames);
      this.logger.log(`Live capture enrollment complete: ${profile.name} (id=${profile.id})`);
      this.sendFn?.(cameraDeviceId, 'vision:enroll_result', { ok: true, name: profile.name });
    } catch (err) {
      this.logger.warn(`Live capture enrollment failed: ${(err as Error).message}`);
      this.sendFn?.(cameraDeviceId, 'vision:enroll_result', { ok: false, error: (err as Error).message });
    }
  }

  setPendingEnrollment(cameraDeviceId: string, userId: string, name: string): void {
    this.pendingEnrollments.set(cameraDeviceId, { userId, name, frames: [] });
  }
}
