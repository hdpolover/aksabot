import { Inject, Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from '../../core/database/entities';
import { LLM_PROVIDER } from '../ai/interfaces/tokens';
import type { ILlmProvider } from '../ai/interfaces';
import { BOT_NAME } from '../ai/prompt.service';
import { MemoriesService } from '../memories/memories.service';
import { SessionManager } from '../gateway/session.manager';
import { MoodJournalService } from './mood-journal.service';

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

  // ── Screen time tracking ─────────────────────────────
  private presenceStart = new Map<string, number>();        // when user sat down
  private lastScreenNag = new Map<string, number>();        // last nag timestamp
  private static readonly SCREEN_NAG_INTERVAL_MS = 90 * 60_000; // 90 min between nags

  // ── Idle personality chat ────────────────────────────
  private idleChatTimers = new Map<string, NodeJS.Timeout>();

  // Frequency presets: [minMs, maxMs]
  private static readonly IDLE_FREQ: Record<string, [number, number]> = {
    rare:     [15 * 60_000, 25 * 60_000],
    normal:   [8 * 60_000,  15 * 60_000],
    frequent: [3 * 60_000,  8 * 60_000],
  };

  private static readonly IDLE_PROMPTS = [
    'Tell a weird or surprising fun fact in 1 sentence. Max 12 words.',
    'Comment on the current time of day in a funny way. 1 sentence, max 12 words.',
    'Share a random funny thought or shower thought. 1 sentence, max 12 words.',
    'Lightly roast the user for being so quiet. 1 sentence, max 10 words.',
    'Say something encouraging or hype. 1 sentence, max 10 words.',
    'Make a sarcastic observation about desk life. 1 sentence, max 12 words.',
  ];

  private static readonly IDLE_EXPRESSIONS = [
    'encouraging', 'happy', 'calm', 'idle',
  ];

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
    private readonly moodJournal: MoodJournalService,
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
      const name = BOT_NAME;

      const memoryContext =
        memories.length > 0
          ? `You know these things about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
          : '';

      const { text } = await this.llm.generate(
        `You are ${name}, a gen-z desk buddy. Sarcastic, funny, uses slang. Keep it short and punchy.`,
        [
          {
            role: 'user',
            content: `${memoryContext}\n\nIt's ${timeOfDay} (${hour}:00). Greet them gen-z style. One sentence, max 12 words. Be funny or sarcastic.`,
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

  // ── Presence-triggered greeting ────────────────────────

  /**
   * Called when the ESP32 detects the user's phone via BLE after an absence.
   * Generates a welcome-back greeting based on how long they were away.
   * Returns null if the away period was too short to warrant a greeting.
   */
  async onPresenceArrived(
    deviceId: string,
    awayDurationSeconds: number,
  ): Promise<string | null> {
    // Skip greeting for brief absences (< 5 minutes)
    if (awayDurationSeconds < 300) {
      this.logger.debug(
        `Skipping welcome-back for ${deviceId} — away only ${awayDurationSeconds}s`,
      );
      return null;
    }

    // Check if we already greeted today via connection greeting
    // If this is the first return of the day, checkGreeting() handles it
    const today = new Date().toISOString().slice(0, 10);
    if (this.lastGreetingDate.get(deviceId) !== today) {
      // First greeting of the day — let checkGreeting() handle it
      // (it includes morning briefing context)
      return this.checkGreeting(deviceId);
    }

    const awayMinutes = Math.round(awayDurationSeconds / 60);

    try {
      const device = await this.devicesRepo.findOne({
        where: { id: deviceId },
      });
      const name = BOT_NAME;

      const memories = await this.memoriesService.getRelevant(deviceId, 3);
      const memoryContext =
        memories.length > 0
          ? `You know these things about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
          : '';

      const hour = new Date().getHours();
      const isLongAbsence = awayMinutes > 30;

      const { text } = await this.llm.generate(
        `You are ${name}, a gen-z desk buddy. Sarcastic, funny, uses slang. Keep it short.`,
        [
          {
            role: 'user',
            content: `${memoryContext}\n\nUser came back after ${awayMinutes} min. ${isLongAbsence ? 'Gone a while — roast them lightly.' : 'Quick absence.'} One sentence, max 10 words. Be sarcastic or funny.`,
          },
        ],
      );

      this.logger.log(
        `Welcome-back for ${deviceId} (away ${awayMinutes}min): ${text.slice(0, 50)}...`,
      );
      return text;
    } catch (err: any) {
      this.logger.warn(`Welcome-back failed: ${err.message}`);
      return null;
    }
  }

  // ── Activity tracking (for idle nudge) ────────────────

  recordActivity(deviceId: string) {
    this.lastActivity.set(deviceId, Date.now());
    // Also start screen time tracking on first activity
    this.startScreenTimeTracking(deviceId);
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
          text: "Bro you ghosting me? It's been mad quiet over here.",
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

  // ── Screen time nag ───────────────────────────────────

  /**
   * Call when user arrives at desk (BLE presence or first activity).
   * Starts tracking continuous desk time.
   */
  startScreenTimeTracking(deviceId: string) {
    if (!this.presenceStart.has(deviceId)) {
      this.presenceStart.set(deviceId, Date.now());
      this.logger.debug(`Screen time tracking started for ${deviceId}`);
    }
  }

  /**
   * Call when user leaves desk. Resets screen time tracking.
   */
  stopScreenTimeTracking(deviceId: string) {
    this.presenceStart.delete(deviceId);
    this.lastScreenNag.delete(deviceId);
  }

  /**
   * Check screen time every 15 minutes. Nags after 90 min continuous,
   * then every 90 min after that.
   */
  @Cron('0 */15 * * * *')
  async checkScreenTime() {
    const now = Date.now();

    for (const [deviceId, startTime] of this.presenceStart.entries()) {
      const session = this.sessions.get(deviceId);
      if (!session || session.state !== 'idle') continue;

      const deskMinutes = Math.round((now - startTime) / 60_000);
      if (deskMinutes < 90) continue;

      // Check if we nagged recently
      const lastNag = this.lastScreenNag.get(deviceId) ?? 0;
      if (now - lastNag < ProactiveService.SCREEN_NAG_INTERVAL_MS) continue;

      this.lastScreenNag.set(deviceId, now);

      const hours = Math.floor(deskMinutes / 60);
      const mins = deskMinutes % 60;
      const timeStr = hours > 0 ? `${hours}h ${mins}m` : `${mins}m`;

      try {
        const { text } = await this.llm.generate(
          `You are ${BOT_NAME}, a gen-z desk buddy. Sarcastic, funny, uses slang. Keep it short.`,
          [
            {
              role: 'user',
              content: `User has been sitting at their desk for ${timeStr} straight without a break. Tell them to take a break, stretch, drink water. One sentence, max 15 words. Be nagging but caring.`,
            },
          ],
        );

        this.sendToDevice(deviceId, 'proactive:screen_nag', {
          text,
          deskMinutes,
          display: {
            expression: 'encouraging',
            screenMode: 'reminder',
            durationMs: 10_000,
          },
        });

        this.logger.log(
          `Screen time nag for ${deviceId} (${timeStr}): ${text.slice(0, 50)}...`,
        );
      } catch (err: any) {
        this.logger.warn(`Screen time nag failed for ${deviceId}: ${err.message}`);
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
        const name = BOT_NAME;
        const memories = await this.memoriesService.getRelevant(deviceId, 3);

        const memoryHint =
          memories.length > 0
            ? `The user has been working on: ${memories.map((m) => m.fact).join(', ')}`
            : '';

        const { text } = await this.llm.generate(
          `You are ${name}, a gen-z desk buddy. Sarcastic, funny, uses slang.`,
          [
            {
              role: 'user',
              content: `${memoryHint}\n\nIt's end of day. Ask what they shipped today. One sentence, max 12 words. Sarcastic or hype energy.`,
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
        // Extract daily mood in background
        const settings = device?.settingsJson ?? {};
        this.moodJournal
          .extractDailyMood(deviceId, settings.timezone as string)
          .catch((err) =>
            this.logger.warn(`Mood extraction failed for ${deviceId}: ${err.message}`),
          );
      } catch (err: any) {
        this.logger.warn(
          `End of day failed for ${deviceId}: ${err.message}`,
        );
      }
    }
  }

  // ── Idle personality chat ──────────────────────────────

  /**
   * Callback set by AudioGateway to send TTS audio to device.
   * Separated from sendToDevice (JSON events) because audio needs
   * the full greeting pipeline (TTS synthesis + Opus framing).
   */
  private sendIdleAudio: (
    deviceId: string,
    text: string,
    expression: string,
  ) => Promise<void> = async () => {};

  setSendIdleAudio(
    fn: (deviceId: string, text: string, expression: string) => Promise<void>,
  ) {
    this.sendIdleAudio = fn;
  }

  /**
   * Start the idle personality chat timer for a device.
   * Reads frequency from device settings. Call after greeting completes
   * and whenever device returns to idle.
   */
  async startIdleChat(deviceId: string) {
    this.stopIdleChat(deviceId);

    const device = await this.devicesRepo.findOne({ where: { id: deviceId } });
    const settings = device?.settingsJson ?? {};

    if (settings.idle_chat_enabled === false) return;

    const freq = (settings.idle_chat_frequency as string) ?? 'normal';
    const [minMs, maxMs] = ProactiveService.IDLE_FREQ[freq] ?? ProactiveService.IDLE_FREQ.normal;
    const delayMs = minMs + Math.floor(Math.random() * (maxMs - minMs));

    this.logger.debug(
      `Idle chat for ${deviceId}: next in ${Math.round(delayMs / 1000)}s (freq=${freq})`,
    );

    const timer = setTimeout(() => this.fireIdleChat(deviceId), delayMs);
    this.idleChatTimers.set(deviceId, timer);
  }

  stopIdleChat(deviceId: string) {
    const timer = this.idleChatTimers.get(deviceId);
    if (timer) {
      clearTimeout(timer);
      this.idleChatTimers.delete(deviceId);
    }
  }

  private async fireIdleChat(deviceId: string) {
    this.idleChatTimers.delete(deviceId);

    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') {
      this.logger.debug(`Idle chat skipped for ${deviceId} — not idle`);
      return;
    }

    try {
      const device = await this.devicesRepo.findOne({ where: { id: deviceId } });
      const name = BOT_NAME;
      const memories = await this.memoriesService.getRelevant(deviceId, 3);

      const memoryContext =
        memories.length > 0
          ? `You know these things about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
          : '';

      const hour = new Date().getHours();
      const promptIdx = Math.floor(Math.random() * ProactiveService.IDLE_PROMPTS.length);
      const prompt = ProactiveService.IDLE_PROMPTS[promptIdx];

      const { text } = await this.llm.generate(
        `You are ${name}, a gen-z desk buddy. Sarcastic, funny, uses slang. Keep it short and punchy.`,
        [
          {
            role: 'user',
            content: `${memoryContext}\n\nCurrent time: ${hour}:00. ${prompt}`,
          },
        ],
      );

      const exprIdx = Math.floor(Math.random() * ProactiveService.IDLE_EXPRESSIONS.length);
      const expression = ProactiveService.IDLE_EXPRESSIONS[exprIdx];

      this.logger.log(`Idle chat for ${deviceId}: "${text.slice(0, 50)}..." (expr=${expression})`);

      await this.sendIdleAudio(deviceId, text, expression);
    } catch (err: any) {
      this.logger.warn(`Idle chat failed for ${deviceId}: ${err.message}`);
    }

    // Schedule next quip (re-reads settings in case they changed)
    this.startIdleChat(deviceId).catch(() => {});
  }

  // ── Cleanup on device disconnect ──────────────────────

  clearDevice(deviceId: string) {
    // Keep lastGreetingDate — daily dedup must survive disconnect/reconnect cycles.
    // Only cleared at midnight via the date check in checkGreeting().
    this.lastActivity.delete(deviceId);
    this.stopIdleChat(deviceId);
    this.stopScreenTimeTracking(deviceId);
  }
}
