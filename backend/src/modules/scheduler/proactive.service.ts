import { Inject, Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from '../../core/database/entities';
import { LLM_PROVIDER } from '../ai/interfaces/tokens';
import type { ILlmProvider } from '../ai/interfaces';
import { MemoriesService } from '../memories/memories.service';
import { SessionManager } from '../gateway/session.manager';

@Injectable()
export class ProactiveService {
  private readonly logger = new Logger(ProactiveService.name);

  // Track first interaction of the day per device
  private lastGreetingDate = new Map<string, string>();
  // Track last activity per device (for idle nudge)
  private lastActivity = new Map<string, number>();
  // Work hours config (default 9-18)
  private workHoursStart = 9;
  private workHoursEnd = 18;

  private sendToDevice: (
    deviceId: string,
    event: string,
    data: any,
  ) => void = () => {};

  constructor(
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
    @Inject(LLM_PROVIDER) private readonly llm: ILlmProvider,
    private readonly memoriesService: MemoriesService,
    private readonly sessions: SessionManager,
  ) {}

  setSendToDevice(fn: (deviceId: string, event: string, data: any) => void) {
    this.sendToDevice = fn;
  }

  // ── Morning briefing ──────────────────────────────────

  /**
   * Called when a device starts its first audio interaction.
   * If it's the first interaction of the day, generates a morning briefing.
   */
  async checkGreeting(deviceId: string): Promise<string | null> {
    const today = new Date().toISOString().slice(0, 10);
    if (this.lastGreetingDate.get(deviceId) === today) {
      return null; // Already greeted today
    }

    this.lastGreetingDate.set(deviceId, today);

    const hour = new Date().getHours();
    let timeOfDay: string;
    if (hour < 12) timeOfDay = 'morning';
    else if (hour < 17) timeOfDay = 'afternoon';
    else if (hour < 21) timeOfDay = 'evening';
    else timeOfDay = 'night';

    try {
      const memories = await this.memoriesService.getRelevant(deviceId, 5);
      const device = await this.devicesRepo.findOne({
        where: { id: deviceId },
      });
      const name = device?.personalityJson?.name ?? 'buddy';

      const memoryContext =
        memories.length > 0
          ? `You know these things about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
          : '';

      const { text } = await this.llm.generate(
        `You are a friendly desk companion named ${name}. ` +
          `It is currently ${timeOfDay} (${hour}:00). Generate a brief, warm ${timeOfDay} greeting. ` +
          `Use an appropriate greeting for the time of day (e.g., "Good morning" before noon, "Good afternoon", "Good evening", or "Hey, still up?" late at night). ` +
          `If you have context about what the user was working on, reference it naturally. ` +
          `Keep it under 30 words. Be conversational, not robotic.`,
        [
          {
            role: 'user',
            content: `${memoryContext}\n\nGenerate a ${timeOfDay} greeting. The current time is ${hour}:00.`,
          },
        ],
      );

      this.logger.log(`Greeting for device ${deviceId}: ${text.slice(0, 50)}...`);
      return text;
    } catch (err: any) {
      this.logger.warn(`Greeting failed: ${err.message}`);
      return null;
    }
  }

  // ── Activity tracking (for idle nudge) ────────────────

  recordActivity(deviceId: string) {
    this.lastActivity.set(deviceId, Date.now());
  }

  // ── Idle nudge check (every 30 minutes) ───────────────

  @Cron('0 */30 * * * *')
  async checkIdleNudges() {
    const now = Date.now();
    const hour = new Date().getHours();

    // Only during work hours
    if (hour < this.workHoursStart || hour >= this.workHoursEnd) return;

    for (const [deviceId, lastTime] of this.lastActivity.entries()) {
      const session = this.sessions.get(deviceId);
      if (!session || session.state !== 'idle') continue;

      const idleMinutes = (now - lastTime) / 60_000;
      if (idleMinutes >= 180) {
        // 3+ hours idle
        this.sendToDevice(deviceId, 'proactive:nudge', {
          text: "Everything okay? You've been quiet for a while.",
          display: {
            expression: 'gentle',
            screenMode: 'reminder',
            durationMs: 8_000,
          },
        });
        // Reset to avoid repeated nudges
        this.lastActivity.set(deviceId, now);
        this.logger.debug(`Idle nudge sent to device ${deviceId}`);
      }
    }
  }

  // ── End of day wind-down (6 PM) ───────────────────────

  @Cron('0 0 18 * * *')
  async handleEndOfDay() {
    for (const [deviceId] of this.lastActivity.entries()) {
      const session = this.sessions.get(deviceId);
      if (!session || session.state !== 'idle') continue;

      try {
        const device = await this.devicesRepo.findOne({
          where: { id: deviceId },
        });
        const name = device?.personalityJson?.name ?? 'buddy';
        const memories = await this.memoriesService.getRelevant(deviceId, 3);

        const memoryHint =
          memories.length > 0
            ? `The user has been working on: ${memories.map((m) => m.fact).join(', ')}`
            : '';

        const { text } = await this.llm.generate(
          `You are ${name}, a friendly desk companion. ` +
            `It's the end of the work day. Generate a brief wind-down message ` +
            `asking what the user accomplished today. Keep it under 25 words. ` +
            `Be warm and encouraging.`,
          [
            {
              role: 'user',
              content: `${memoryHint}\n\nGenerate an end-of-day wrap-up message.`,
            },
          ],
        );

        this.sendToDevice(deviceId, 'proactive:briefing', {
          type: 'end_of_day',
          text,
          display: {
            expression: 'calm',
            screenMode: 'reminder',
            durationMs: 15_000,
          },
        });
      } catch (err: any) {
        this.logger.warn(
          `End of day failed for ${deviceId}: ${err.message}`,
        );
      }
    }
  }

  // ── Cleanup on device disconnect ──────────────────────

  clearDevice(deviceId: string) {
    // Keep lastGreetingDate — daily dedup must survive disconnect/reconnect cycles.
    // Only cleared at midnight via the date check in checkGreeting().
    this.lastActivity.delete(deviceId);
  }
}
