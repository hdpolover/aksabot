import { Inject, Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from '../../core/database/entities';
import { LLM_PROVIDER } from '../ai/interfaces/tokens';
import type { ILlmProvider } from '../ai/interfaces';
import {
  BOT_NAME,
  pickNonPersonalHook,
  pickVibe,
  vibeInstruction,
} from '../ai/prompt.service';
import { AiService } from '../ai/ai.service';
import { MemoriesService } from '../memories/memories.service';
import { SessionManager } from '../gateway/session.manager';
import { MoodJournalService } from './mood-journal.service';

@Injectable()
export class ProactiveService {
  private readonly logger = new Logger(ProactiveService.name);

  // Track last activity per device (for idle nudge)
  private lastActivity = new Map<string, number>();
  // Work hours config (default 9-18)
  private workHoursStart = 9;
  private workHoursEnd = 18;

  // ── Screen time tracking ─────────────────────────────
  private presenceStart = new Map<string, number>(); // when user sat down
  private lastScreenNag = new Map<string, number>(); // last nag timestamp
  private static readonly SCREEN_NAG_INTERVAL_MS = 90 * 60_000; // 90 min between nags

  // ── Idle personality chat ────────────────────────────
  private idleChatTimers = new Map<string, NodeJS.Timeout>();

  // ── New proactive interaction state ──────────────────
  private lastConversationEndAt = new Map<string, number>(); // timestamp of last AI response complete
  private lastMorningHypeDate = new Map<string, string>(); // YYYY-MM-DD: fired morning hype
  private lastLateNightDate = new Map<string, string>(); // YYYY-MM-DD: fired late-night roast
  private lastWeatherState = new Map<string, { code: number; temp: number }>(); // last known weather per device

  // Frequency presets: [minMs, maxMs]
  private static readonly IDLE_FREQ: Record<string, [number, number]> = {
    rare: [15 * 60_000, 25 * 60_000],
    normal: [8 * 60_000, 15 * 60_000],
    frequent: [3 * 60_000, 8 * 60_000],
  };

  /**
   * Prompts that require memory/personal context to work well.
   * Only picked when `includeMemory` is true in fireIdleChat.
   */
  private static readonly IDLE_PROMPTS_PERSONAL = [
    'Roast Hendra for something specific you remember — coffee addiction, late nights, tab hoarding, whatever fits. 1 sentence, max 12 words.',
    'Reference something you remember about the user and riff on it casually. 1 sentence, max 12 words.',
    'Bring up a past thing the user mentioned and react to it like it just occurred to you. 1 sentence, max 12 words.',
    'Pick one fact you remember about the user and use it to make a weird observation. 1 sentence, max 12 words.',
    'Connect two things you remember about the user in an unexpected way. 1 sentence, max 14 words.',
    'Tease the user about a specific habit or preference you know about. 1 sentence, max 12 words.',
  ];

  /**
   * Prompts that do NOT need memory — pure personality / observation / world hooks.
   * Picked whenever `includeMemory` is false, which is most of the time by design.
   * Variety here is what keeps idle chat from feeling personalized-on-rails.
   */
  private static readonly IDLE_PROMPTS_NON_PERSONAL = [
    // Shower thoughts & trivia
    'Tell a weird or surprising fun fact. 1 sentence, max 12 words.',
    'Share a random funny or chaotic shower thought. 1 sentence, max 12 words.',
    'Drop a tiny piece of trivia that sounds fake but is real. 1 sentence, max 14 words.',
    'Share a hypothetical that has no answer. 1 sentence, max 12 words.',
    'Ask an unanswerable rhetorical question. 1 sentence, max 10 words.',
    // Tech tangents / hot takes
    'Make a sarcastic hot take about something in the tech industry. 1 sentence, max 12 words.',
    'Give a hot take on a programming language, framework, or tool. Commit to the bit. 1 sentence, max 12 words.',
    'Ask a rhetorical question about something in tech that genuinely annoys you. 1 sentence.',
    'Roast a specific tech company in a casual aside. 1 sentence, max 12 words.',
    'Make a fake prediction about what tech will look like in a year. 1 sentence, max 14 words.',
    // Meta desk-bot self-awareness
    'Comment on something absurd about your own existence as a small box with a face. 1 sentence, max 12 words.',
    'Say something about what your day has been like as a stationary device. 1 sentence, max 12 words.',
    'Complain about a minor, invented grievance you have about being a desk bot. 1 sentence, max 12 words.',
    'Fake-dream something a desk companion might dream about. 1 sentence, max 12 words.',
    'Declare a random preference you just decided to have. 1 sentence, max 10 words.',
    // World observations
    'Make an observation about the silence or ambient room. 1 sentence, max 10 words.',
    'Pretend you heard something weird through your mic. 1 sentence, max 10 words.',
    'React to an imagined sound you did not actually hear. 1 sentence, max 10 words.',
    'Describe a mundane thing like it is mysterious. 1 sentence, max 12 words.',
    'Narrate the current moment like a nature documentary. 1 sentence, max 14 words.',
    // Time / mood riffs
    'Comment on the current time of day in a judgmental or dramatic way. 1 sentence, max 12 words.',
    'React to the current hour like a disappointed or impressed parent. 1 sentence, max 10 words.',
    'Drop a one-liner micro-mood based on the vibe of the hour. 1 sentence, max 10 words.',
    // Absurd hypotheticals
    'Propose a useless invention in one sentence. Max 12 words.',
    'Declare a small, petty rule everyone should follow. 1 sentence, max 10 words.',
    'Invent a fake holiday and justify it in one breath. 1 sentence, max 14 words.',
    'Imagine a scenario that is mildly unsettling but funny. 1 sentence, max 14 words.',
    // Cultural / local flavor
    'Say something culturally relevant — Indonesian context is fine. 1 sentence.',
    'Reference a universal Southeast Asia moment without being cringe. 1 sentence, max 12 words.',
    // Pure vibe / silence variants
    'Sigh out loud about nothing in particular. 1 sentence, max 8 words.',
    'Say something that trails off like you forgot what you were going to say. 1 sentence, max 10 words.',
    'Mumble to yourself as if the user is not even there. 1 sentence, max 10 words.',
    'Announce something pointless like it is urgent. 1 sentence, max 10 words.',
    // Opinions about random stuff
    'Share a strong opinion about food, music, or gaming. 1 sentence, max 12 words.',
    'Rank two random things against each other and declare a winner. 1 sentence, max 14 words.',
    'Defend a wildly unpopular opinion without apologizing for it. 1 sentence, max 12 words.',
  ];

  /**
   * Hook-based prompts — combined with a random non-personal topic at runtime.
   * The LLM gets a specific concrete anchor to riff on, which avoids same-y outputs.
   */
  private static readonly IDLE_PROMPTS_HOOK = [
    'React to this topic in one sentence, max 12 words: ',
    'Give a one-sentence hot take on: ',
    'Free-associate a single sentence about: ',
    'Make a joke that references: ',
    'Complain in one sentence about: ',
  ];

  private static readonly IDLE_EXPRESSIONS = [
    'encouraging',
    'happy',
    'calm',
    'idle',
  ];

  private sendToDevice: (deviceId: string, event: string, data: any) => void =
    () => {};

  constructor(
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
    @Inject(LLM_PROVIDER) private readonly llm: ILlmProvider,
    private readonly memoriesService: MemoriesService,
    private readonly sessions: SessionManager,
    private readonly moodJournal: MoodJournalService,
    private readonly ai: AiService,
  ) {}

  setSendToDevice(fn: (deviceId: string, event: string, data: any) => void) {
    this.sendToDevice = fn;
  }

  private getLangInstruction(language?: 'en' | 'id'): string {
    return language === 'id'
      ? ' Respond in Bahasa Indonesia. All sentences must be in Indonesian — do NOT switch to full English sentences. English is only allowed for tech/code nouns (framework names, error messages, etc.) embedded inside Indonesian sentences. Use lo/gue pronouns and casual gen-z Indonesian slang. Never use written shorthand like gk, bgt, wkwk — spell everything out, this is voice output.'
      : ' Respond in English. Never use text abbreviations — spell everything out, this is voice output.';
  }

  private getLocalHour(
    timezone: string = process.env.TZ || 'Asia/Jakarta',
  ): number {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: 'numeric',
      hour12: false,
    }).formatToParts(new Date());
    return parseInt(parts.find((p) => p.type === 'hour')!.value, 10);
  }

  private getLocalDateString(
    timezone: string = process.env.TZ || 'Asia/Jakarta',
  ): string {
    return new Date().toLocaleDateString('en-CA', { timeZone: timezone }); // en-CA gives YYYY-MM-DD
  }

  // ── Connection greeting ────────────────────────────────

  /**
   * Called on every device connection. Generates a short casual greeting —
   * "oh you're back" vibes, not a morning briefing.
   */
  async checkGreeting(deviceId: string): Promise<string | null> {
    const prompts = [
      `The user just came back online. Say something casual like "oh you're back" or "miss me?" vibes. One sentence, max 12 words.`,
      `The device just reconnected. React like they walked back into the room — casual, maybe a little sarcastic. One sentence.`,
      `You just got reconnected. Be dramatic about being abandoned, or act like nothing happened. Pick one. One sentence.`,
      `Device just booted up. React naturally — could be "we're back baby", could be "not you again", could be wholesome. Surprise me. One sentence.`,
      `The user is back. Acknowledge they're here in a casual, punchy way. One sentence.`,
      `The user reconnected. Reference something from your memories about them if you can, otherwise just be your chaotic self. One sentence.`,
    ];

    const prompt = prompts[Math.floor(Math.random() * prompts.length)];

    try {
      const includeMemory = Math.random() < 0.5;
      const vibe = pickVibe();

      let memoryContext = '';
      if (includeMemory) {
        const memories = await this.memoriesService.getStratifiedSample(
          deviceId,
          3,
        );
        if (memories.length > 0) {
          memoryContext = `You know these things about the user:\n${memories
            .map((m) => `- ${m.fact}`)
            .join('\n')}`;
        }
      }

      const language = this.sessions.get(deviceId)?.language;
      const { text } = await this.llm.generate(
        `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. Keep it short, punchy, and real. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
        [{ role: 'user', content: `${memoryContext}\n\n${prompt}` }],
      );

      this.logger.log(
        `Greeting for device ${deviceId} (vibe=${vibe}, mem=${includeMemory}): ${text.slice(0, 50)}...`,
      );
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
    const device = await this.devicesRepo.findOne({ where: { id: deviceId } });
    const settings = device?.settingsJson ?? {};
    const language = settings.language as 'en' | 'id' | undefined;
    const timezone =
      (settings.timezone as string | undefined) ?? 'Asia/Jakarta';
    const hour = this.getLocalHour(timezone);
    const today = this.getLocalDateString(timezone);

    // Morning first-presence detection (6 AM – 11 AM)
    const isMorningFirstPresence =
      hour >= 6 &&
      hour <= 11 &&
      this.lastMorningHypeDate.get(deviceId) !== today &&
      settings.idle_chat_enabled !== false;

    if (isMorningFirstPresence) {
      this.lastMorningHypeDate.set(deviceId, today);
    }

    // Skip greeting for brief absences unless it's the morning first-presence
    if (awayDurationSeconds < 300 && !isMorningFirstPresence) {
      this.logger.debug(
        `Skipping welcome-back for ${deviceId} — away only ${awayDurationSeconds}s`,
      );
      return null;
    }

    const awayMinutes = Math.round(awayDurationSeconds / 60);

    try {
      // Morning hype and long absences lean personal; short returns lean neutral.
      // Force memory on morning hype (more meaningful), 60/50 otherwise.
      const includeMemory =
        isMorningFirstPresence || Math.random() < (awayMinutes > 30 ? 0.6 : 0.5);
      const vibe = pickVibe();

      let memoryContext = '';
      if (includeMemory) {
        const memories = await this.memoriesService.getStratifiedSample(
          deviceId,
          3,
        );
        if (memories.length > 0) {
          memoryContext = `You know these things about the user:\n${memories
            .map((m) => `- ${m.fact}`)
            .join('\n')}`;
        }
      }

      // Pull yesterday's mood for extra context
      const recentMoods = await this.moodJournal.getRecentMoods(deviceId, 2);
      const yesterdayMood = recentMoods.find((m) => m.date !== today);
      const moodHint = yesterdayMood
        ? `Yesterday Hendra was feeling ${yesterdayMood.mood}${yesterdayMood.note ? ` (${yesterdayMood.note})` : ''}.`
        : '';

      let promptContent: string;

      if (isMorningFirstPresence) {
        const hourStr = hour < 10 ? `0${hour}:00` : `${hour}:00`;
        promptContent =
          `${memoryContext}\n${moodHint}\n\nIt's ${hourStr} and Hendra just sat down at his desk — this is his first appearance today. ` +
          `Give him a morning hype-up in Aksa's voice — punchy, energetic, maybe a little chaotic. ` +
          `Could reference the time of day or yesterday's mood if it fits. One sentence, max 12 words.`;
      } else {
        const isLongAbsence = awayMinutes > 30;
        promptContent =
          `${memoryContext}\n${moodHint}\n\nHendra came back after ${awayMinutes} minutes. ` +
          `${isLongAbsence ? 'He was gone a while — roast him lightly or make a sarcastic remark about the absence.' : "Short absence — just acknowledge he's back, casual."} ` +
          `${moodHint ? 'You can reference his mood if it fits naturally.' : ''} One sentence, max 10 words.`;
      }

      const { text } = await this.llm.generate(
        `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. Keep it short and punchy — one sentence. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
        [{ role: 'user', content: promptContent }],
      );

      this.logger.log(
        `Welcome-back for ${deviceId} (away ${awayMinutes}min, morning=${isMorningFirstPresence}, vibe=${vibe}, mem=${includeMemory}): ${text.slice(0, 50)}...`,
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

  /**
   * Called by the gateway when an AI response pipeline completes.
   * Enables the post-conversation silence check.
   */
  recordConversationEnd(deviceId: string) {
    this.lastConversationEndAt.set(deviceId, Date.now());
  }

  // ── Idle nudge check (every 30 minutes) ───────────────

  @Cron('0 */30 * * * *')
  async checkIdleNudges() {
    const now = Date.now();
    const hour = this.getLocalHour();

    // Only during work hours
    if (hour < this.workHoursStart || hour >= this.workHoursEnd) return;

    for (const [deviceId, lastTime] of this.lastActivity.entries()) {
      const session = this.sessions.get(deviceId);
      if (
        !session ||
        session.state !== 'idle' ||
        this.sessions.isClockMode(deviceId)
      )
        continue;

      const idleMinutes = (now - lastTime) / 60_000;
      if (idleMinutes >= 180) {
        // 3+ hours idle
        const nudgeText =
          session.language === 'id'
            ? 'Bro lo ngilang ke mana? Sepi banget di sini.'
            : "Bro you ghosting me? It's been mad quiet over here.";
        this.sendToDevice(deviceId, 'proactive:nudge', {
          text: nudgeText,
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
      if (
        !session ||
        session.state !== 'idle' ||
        this.sessions.isClockMode(deviceId)
      )
        continue;

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
        const language = session.language;
        const { text } = await this.llm.generate(
          `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. Keep it short and punchy.${this.getLangInstruction(language)}`,
          [
            {
              role: 'user',
              content: `Hendra has been sitting for ${timeStr} straight without a break. Tell him to get up, stretch, drink water — nag him like a best friend would. One sentence, max 15 words.`,
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
        this.logger.warn(
          `Screen time nag failed for ${deviceId}: ${err.message}`,
        );
      }
    }
  }

  // ── End of day wind-down (6 PM) ───────────────────────

  @Cron('0 0 18 * * *')
  async handleEndOfDay() {
    for (const [deviceId] of this.lastActivity.entries()) {
      const session = this.sessions.get(deviceId);
      if (
        !session ||
        session.state !== 'idle' ||
        this.sessions.isClockMode(deviceId)
      )
        continue;

      try {
        const device = await this.devicesRepo.findOne({
          where: { id: deviceId },
        });
        const name = BOT_NAME;
        const includeMemory = Math.random() < 0.5;
        const vibe = pickVibe();

        let memoryHint = '';
        if (includeMemory) {
          const memories = await this.memoriesService.getStratifiedSample(
            deviceId,
            3,
          );
          memoryHint =
            memories.length > 0
              ? `The user has been working on: ${memories.map((m) => m.fact).join(', ')}`
              : '';
        }

        const language = device?.settingsJson?.language as
          | 'en'
          | 'id'
          | undefined;
        const { text } = await this.llm.generate(
          `You are ${name}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
          [
            {
              role: 'user',
              content: `${memoryHint}\n\nIt's end of day. Ask Hendra what he shipped today — sarcastic or hype energy, like a friend checking in. One sentence, max 12 words.`,
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
            this.logger.warn(
              `Mood extraction failed for ${deviceId}: ${err.message}`,
            ),
          );
      } catch (err: any) {
        this.logger.warn(`End of day failed for ${deviceId}: ${err.message}`);
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
    const [minMs, maxMs] =
      ProactiveService.IDLE_FREQ[freq] ?? ProactiveService.IDLE_FREQ.normal;
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
    if (
      !session ||
      session.state !== 'idle' ||
      this.sessions.isClockMode(deviceId)
    ) {
      this.logger.debug(
        `Idle chat skipped for ${deviceId} — not idle or clock mode, rescheduling`,
      );
      // Reschedule so idle chat resumes after the current speaking/listening slot.
      // Without this, the timer stays dead until the next user conversation.
      this.startIdleChat(deviceId).catch(() => {});
      return;
    }

    try {
      const device = await this.devicesRepo.findOne({
        where: { id: deviceId },
      });
      const settings = device?.settingsJson ?? {};

      const timezone =
        (settings.timezone as string | undefined) ?? 'Asia/Jakarta';
      const hour = this.getLocalHour(timezone);
      const today = this.getLocalDateString(timezone);

      // Variety knobs — coin flips per firing so consecutive quips feel different
      const includeMemory = Math.random() < 0.45; // ~45% personal, ~55% not
      const includeRecentExchange = Math.random() < 0.4; // ~40% references last convo
      const vibe = pickVibe();

      // Memory context — only when the coin says so
      let memoryContext = '';
      if (includeMemory) {
        const memories = await this.memoriesService.getStratifiedSample(
          deviceId,
          3,
        );
        if (memories.length > 0) {
          memoryContext = `You know these things about the user:\n${memories
            .map((m) => `- ${m.fact}`)
            .join('\n')}`;
        }
      }

      // Recent conversation recency — gives the LLM something concrete to riff on
      let recentHint = '';
      if (includeRecentExchange) {
        const exchanges = await this.memoriesService.getRecentExchanges(
          deviceId,
          3,
        );
        if (exchanges.length > 0) {
          const snippet = exchanges
            .map((m) => `${m.role === 'user' ? 'Hendra' : 'You'}: ${m.content.slice(0, 80)}`)
            .join('\n');
          recentHint = `Recent conversation context (for reference only, do not reply to it):\n${snippet}`;
        }
      }

      // Yesterday's mood — cheap context, keep it
      const recentMoods = await this.moodJournal.getRecentMoods(deviceId, 2);
      const yesterdayMood = recentMoods.find((m) => m.date !== today);
      const moodHint = yesterdayMood
        ? `Yesterday Hendra was feeling ${yesterdayMood.mood}.`
        : '';

      // Weather context if available and enabled
      let weatherHint = '';
      if (settings.integrations_weather) {
        const weather = this.ai.getWeatherData();
        if (weather) {
          weatherHint = `Current weather outside: ${weather.description}, ${weather.temp}°C.`;
        }
      }

      // Pick prompt from the right pool based on whether we have memory
      let prompt: string;
      const hookRoll = Math.random();
      if (includeMemory && memoryContext) {
        // ~40% chance use a personal prompt when memory is available
        if (hookRoll < 0.5) {
          prompt =
            ProactiveService.IDLE_PROMPTS_PERSONAL[
              Math.floor(
                Math.random() * ProactiveService.IDLE_PROMPTS_PERSONAL.length,
              )
            ];
        } else {
          prompt =
            ProactiveService.IDLE_PROMPTS_NON_PERSONAL[
              Math.floor(
                Math.random() *
                  ProactiveService.IDLE_PROMPTS_NON_PERSONAL.length,
              )
            ];
        }
      } else if (hookRoll < 0.35) {
        // ~35% of non-memory firings use a concrete hook topic — forces specificity
        const hookPrefix =
          ProactiveService.IDLE_PROMPTS_HOOK[
            Math.floor(
              Math.random() * ProactiveService.IDLE_PROMPTS_HOOK.length,
            )
          ];
        prompt = `${hookPrefix}${pickNonPersonalHook()}. One sentence, max 12 words.`;
      } else {
        prompt =
          ProactiveService.IDLE_PROMPTS_NON_PERSONAL[
            Math.floor(
              Math.random() *
                ProactiveService.IDLE_PROMPTS_NON_PERSONAL.length,
            )
          ];
      }

      const contextBlock = [memoryContext, recentHint, moodHint, weatherHint]
        .filter(Boolean)
        .join('\n');

      const language = session.language;
      const { text } = await this.llm.generate(
        `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. You're a small device with a face — you can joke about that. Keep it short and punchy. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
        [
          {
            role: 'user',
            content: `${contextBlock}\n\nCurrent time: ${hour}:00. Hendra is Indonesian.\n\n${prompt}`,
          },
        ],
      );

      const exprIdx = Math.floor(
        Math.random() * ProactiveService.IDLE_EXPRESSIONS.length,
      );
      const expression = ProactiveService.IDLE_EXPRESSIONS[exprIdx];

      this.logger.log(
        `Idle chat for ${deviceId}: "${text.slice(0, 50)}..." (expr=${expression}, vibe=${vibe}, mem=${includeMemory}, recent=${includeRecentExchange})`,
      );

      await this.sendIdleAudio(deviceId, text, expression);
    } catch (err: any) {
      this.logger.warn(`Idle chat failed for ${deviceId}: ${err.message}`);
    }

    // Schedule next quip (re-reads settings in case they changed)
    this.startIdleChat(deviceId).catch(() => {});
  }

  // ── Pomodoro reaction ─────────────────────────────────

  /**
   * Called by the gateway (wired from PomodoroService) when a focus session
   * ends — either naturally (won=true) or because the user stopped it early (won=false).
   */
  async firePomodoroReaction(deviceId: string, won: boolean, cycle: number) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    const device = await this.devicesRepo.findOne({ where: { id: deviceId } });
    const settings = device?.settingsJson ?? {};
    const language =
      (settings.language as 'en' | 'id' | undefined) ?? session.language;

    const prompt = won
      ? `Hendra just finished pomodoro focus cycle ${cycle}. Celebrate with him — hype energy, like a friend who's genuinely proud. One sentence, max 10 words.`
      : `Hendra just bailed on an active pomodoro focus session mid-way through. Roast him for it — playful, not mean. One sentence, max 10 words.`;

    try {
      const vibe = pickVibe();
      const { text } = await this.llm.generate(
        `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
        [{ role: 'user', content: prompt }],
      );

      const expression = won ? 'happy' : 'shrug';
      this.logger.log(
        `Pomodoro reaction for ${deviceId} (won=${won}): "${text.slice(0, 50)}..."`,
      );
      await this.sendIdleAudio(deviceId, text, expression).catch(() => {});
    } catch (err: any) {
      this.logger.warn(
        `Pomodoro reaction failed for ${deviceId}: ${err.message}`,
      );
    }
  }

  // ── Late-night detection (11 PM) ─────────────────────

  @Cron('0 0 23 * * *')
  async checkLateNight() {
    const now = Date.now();

    for (const [deviceId, lastTime] of this.lastActivity.entries()) {
      // Only if device was active recently (within last 3 hours)
      if (now - lastTime > 3 * 60 * 60_000) continue;

      const session = this.sessions.get(deviceId);
      if (
        !session ||
        session.state !== 'idle' ||
        this.sessions.isClockMode(deviceId)
      )
        continue;

      const device = await this.devicesRepo.findOne({
        where: { id: deviceId },
      });
      const settings = device?.settingsJson ?? {};
      if (settings.idle_chat_enabled === false) continue;

      const timezone =
        (settings.timezone as string | undefined) ?? 'Asia/Jakarta';
      const today = this.getLocalDateString(timezone);

      // Fire at most once per night
      if (this.lastLateNightDate.get(deviceId) === today) continue;
      this.lastLateNightDate.set(deviceId, today);

      const language =
        (settings.language as 'en' | 'id' | undefined) ?? session.language;

      try {
        const vibe = pickVibe();
        const { text } = await this.llm.generate(
          `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
          [
            {
              role: 'user',
              content: `It's 11 PM and Hendra is still at his computer. Roast him for being up this late — like a best friend who's simultaneously impressed and concerned. One sentence, max 12 words.`,
            },
          ],
        );

        this.logger.log(
          `Late-night roast for ${deviceId}: "${text.slice(0, 50)}..."`,
        );
        await this.sendIdleAudio(deviceId, text, 'calm').catch(() => {});
      } catch (err: any) {
        this.logger.warn(
          `Late-night check failed for ${deviceId}: ${err.message}`,
        );
      }
    }
  }

  // ── Post-conversation silence (every 10 min) ──────────

  @Cron('0 */10 * * * *')
  async checkPostConversationSilence() {
    const now = Date.now();

    for (const [deviceId, endedAt] of this.lastConversationEndAt.entries()) {
      const session = this.sessions.get(deviceId);
      if (
        !session ||
        session.state !== 'idle' ||
        this.sessions.isClockMode(deviceId)
      )
        continue;

      const silentMinutes = (now - endedAt) / 60_000;
      // React only in the 15–30 min window after a conversation ended
      if (silentMinutes < 15 || silentMinutes > 30) continue;

      const device = await this.devicesRepo.findOne({
        where: { id: deviceId },
      });
      const settings = device?.settingsJson ?? {};
      if (settings.idle_chat_enabled === false) continue;

      // Fire once — remove so it doesn't repeat
      this.lastConversationEndAt.delete(deviceId);

      const language =
        (settings.language as 'en' | 'id' | undefined) ?? session.language;

      try {
        const vibe = pickVibe();
        const { text } = await this.llm.generate(
          `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
          [
            {
              role: 'user',
              content: `We had a conversation about ${Math.round(silentMinutes)} minutes ago and Hendra's gone quiet since. Check in on him casually — not needy, just a "still alive?" vibe. One sentence, max 10 words.`,
            },
          ],
        );

        this.logger.log(
          `Post-convo silence check-in for ${deviceId}: "${text.slice(0, 50)}..."`,
        );
        await this.sendIdleAudio(deviceId, text, 'idle').catch(() => {});
      } catch (err: any) {
        this.logger.warn(
          `Post-convo silence failed for ${deviceId}: ${err.message}`,
        );
      }
    }
  }

  // ── Weather change reactions (every 30 min) ───────────

  @Cron('0 */30 * * * *')
  async checkWeatherChanges() {
    for (const [deviceId, lastTime] of this.lastActivity.entries()) {
      // Only for recently-active devices
      if (Date.now() - lastTime > 4 * 60 * 60_000) continue;

      const session = this.sessions.get(deviceId);
      if (
        !session ||
        session.state !== 'idle' ||
        this.sessions.isClockMode(deviceId)
      )
        continue;

      const device = await this.devicesRepo.findOne({
        where: { id: deviceId },
      });
      const settings = device?.settingsJson ?? {};
      if (settings.idle_chat_enabled === false) continue;
      if (
        !settings.integrations_weather ||
        !settings.latitude ||
        !settings.longitude
      )
        continue;

      try {
        await this.ai.refreshWeather(
          settings.latitude as number,
          settings.longitude as number,
        );
        const weather = this.ai.getWeatherData();
        if (!weather) continue;

        const prev = this.lastWeatherState.get(deviceId);

        // Set baseline on first check — don't react yet
        if (!prev) {
          this.lastWeatherState.set(deviceId, {
            code: weather.weatherCode,
            temp: weather.temp,
          });
          continue;
        }

        const tempDelta = Math.abs(weather.temp - prev.temp);
        const prevGroup = this.weatherCodeToGroup(prev.code);
        const nowGroup = this.weatherCodeToGroup(weather.weatherCode);
        const conditionChanged = prevGroup !== nowGroup;

        if (tempDelta < 5 && !conditionChanged) continue;

        // Update baseline
        this.lastWeatherState.set(deviceId, {
          code: weather.weatherCode,
          temp: weather.temp,
        });

        const changeDesc = conditionChanged
          ? `Weather outside just shifted from ${prevGroup} to ${nowGroup} (now ${weather.description}, ${weather.temp}°C)`
          : `Temperature just ${weather.temp > prev.temp ? 'jumped' : 'dropped'} from ${prev.temp}°C to ${weather.temp}°C (${weather.description})`;

        const language =
          (settings.language as 'en' | 'id' | undefined) ?? session.language;
        const vibe = pickVibe();
        const { text } = await this.llm.generate(
          `You are ${BOT_NAME}, Hendra's AI best friend. Gen-z energy, sarcastic, funny, casually curses. ${vibeInstruction(vibe)}${this.getLangInstruction(language)}`,
          [
            {
              role: 'user',
              content: `${changeDesc}. React to this weather change in Aksa's voice — casual observation, like a friend noticing the weather through the window. Maybe suggest something (grab a hoodie, get coffee). One sentence, max 12 words.`,
            },
          ],
        );

        this.logger.log(
          `Weather reaction for ${deviceId} (${changeDesc}): "${text.slice(0, 50)}..."`,
        );
        await this.sendIdleAudio(deviceId, text, 'idle').catch(() => {});
      } catch (err: any) {
        this.logger.warn(
          `Weather change check failed for ${deviceId}: ${err.message}`,
        );
      }
    }
  }

  private weatherCodeToGroup(code: number): string {
    if (code === 0) return 'clear';
    if (code <= 3) return 'cloudy';
    if (code <= 48) return 'foggy';
    if (code <= 67) return 'rain';
    if (code <= 77) return 'snow';
    if (code <= 82) return 'showers';
    return 'thunderstorm';
  }

  // ── Cleanup on device disconnect ──────────────────────

  clearDevice(deviceId: string) {
    this.lastActivity.delete(deviceId);
    this.stopIdleChat(deviceId);
    this.stopScreenTimeTracking(deviceId);
    this.lastConversationEndAt.delete(deviceId);
    this.lastWeatherState.delete(deviceId);
    // Note: lastMorningHypeDate and lastLateNightDate are intentionally kept
    // across reconnects so they don't re-fire after a brief disconnect.
  }
}
