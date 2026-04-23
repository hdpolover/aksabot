import { Injectable, Logger } from '@nestjs/common';
import { VisionService } from './vision.service';
import { SessionManager } from '../gateway/session.manager';
import { DevicesService } from '../devices/devices.service';

export interface PendingEnrollment {
  userId: string;
  name: string;
  frames: Buffer[];
}

interface FrameVote {
  name: string | null;
  unknown: boolean;
  confidence: number;
}

/** Sliding window size for temporal smoothing. */
const VOTE_WINDOW = 5;
/** Minimum votes in window for identity to be emitted. */
const VOTE_THRESHOLD = 3;

@Injectable()
export class VisionGatewayHandler {
  private readonly logger = new Logger(VisionGatewayHandler.name);
  private sendFn: ((deviceId: string, event: string, data: any) => void) | null = null;
  private pendingEnrollments = new Map<string, PendingEnrollment>();

  // Per-camera sliding window of last VOTE_WINDOW recognition results.
  // Only emit face:identity when VOTE_THRESHOLD consecutive frames agree.
  private voteWindows = new Map<string, FrameVote[]>();

  constructor(
    private readonly visionService: VisionService,
    private readonly sessions: SessionManager,
    private readonly devicesService: DevicesService,
  ) {}

  setSendFn(fn: (deviceId: string, event: string, data: any) => void) {
    this.sendFn = fn;
  }

  /** Called by AudioGateway when a vision:frame binary message arrives from ESP32-CAM. */
  async handleFrame(cameraDeviceId: string, jpegBuffer: Buffer): Promise<void> {
    const device = await this.devicesService.findByIdInternal(cameraDeviceId);
    if (!device) return;

    const userId = device.userId;
    const pairedDeviceId = (device.settingsJson as any)?.pairedDeviceId as string | undefined;

    const embedding = await this.visionService.detectAndEmbed(jpegBuffer);

    const vote: FrameVote = embedding
      ? await this.visionService.findBestMatch(userId, embedding).then(r => ({
          name: r.name, unknown: r.unknown, confidence: r.confidence,
        }))
      : { name: null, unknown: true, confidence: 0 };

    // Temporal smoothing: slide window, check majority
    const window = this.voteWindows.get(cameraDeviceId) ?? [];
    window.push(vote);
    if (window.length > VOTE_WINDOW) window.shift();
    this.voteWindows.set(cameraDeviceId, window);

    const agreed = this.majoritySmoother(window);
    if (!agreed) return; // window hasn't converged yet

    this.logger.debug(
      `Face identity (${window.length}-frame vote): ${agreed.unknown ? 'unknown' : agreed.name}`,
    );

    if (pairedDeviceId) {
      this.sessions.setCurrentIdentity(pairedDeviceId, {
        name: agreed.name,
        unknown: agreed.unknown,
      });
      this.sendFn?.(pairedDeviceId, 'face:identity', {
        name: agreed.name,
        confidence: agreed.confidence,
        unknown: agreed.unknown,
      });
    }
  }

  /**
   * Returns the agreed identity if VOTE_THRESHOLD or more frames in the window
   * agree on the same name (including unknown). Returns null if no consensus yet.
   * Confidence is the average across agreeing frames.
   */
  private majoritySmoother(window: FrameVote[]): FrameVote | null {
    if (window.length < VOTE_WINDOW) return null;

    const counts = new Map<string | null, { count: number; totalConf: number }>();
    for (const vote of window) {
      const key = vote.unknown ? null : vote.name;
      const entry = counts.get(key) ?? { count: 0, totalConf: 0 };
      counts.set(key, { count: entry.count + 1, totalConf: entry.totalConf + vote.confidence });
    }

    for (const [name, { count, totalConf }] of counts) {
      if (count >= VOTE_THRESHOLD) {
        return {
          name,
          unknown: name === null,
          confidence: totalConf / count,
        };
      }
    }
    return null;
  }

  /** Called by AudioGateway when vision:enroll_frames arrives from ESP32-CAM capture. */
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
