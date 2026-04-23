import { Inject, Logger, OnModuleInit, forwardRef } from '@nestjs/common';
import {
  WebSocketGateway,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import type { IncomingMessage } from 'http';
import { existsSync, createReadStream, mkdirSync, unlink } from 'fs';
import type WebSocket from 'ws';
import type Redis from 'ioredis';
import { AuthService } from '../auth/auth.service';
import { AiService } from '../ai/ai.service';
import { MemoriesService } from '../memories/memories.service';
import { SchedulerService } from '../scheduler/scheduler.service';
import { PomodoroService } from '../scheduler/pomodoro.service';
import { ProactiveService } from '../scheduler/proactive.service';
import { MoodJournalService } from '../scheduler/mood-journal.service';
import { VoiceCommandService } from './voice-command.service';
import { SessionManager } from './session.manager';
import { ConversationPersistence } from './conversation.persistence';
import { VisionGatewayHandler } from '../vision/vision-gateway.handler';
import type { SttResult, IAudioCodec } from '../ai/interfaces';
import { AUDIO_CODEC } from '../ai/interfaces/tokens';
import { IntercomSessionService } from './intercom-session.service';
import { REDIS_CLIENT } from '../../core/cache/redis.provider';

interface WsMessage {
  event: string;
  data?: any;
}

@WebSocketGateway({ path: '/ws' })
export class AudioGateway
  implements OnGatewayConnection, OnGatewayDisconnect, OnModuleInit
{
  private readonly logger = new Logger(AudioGateway.name);

  private socketToDevice = new Map<WebSocket, string>();
  private deviceToSocket = new Map<string, WebSocket>();
  private lastPong = new Map<string, number>(); // deviceId → timestamp of last pong
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;

  private static readonly AUDIO_RATE_LIMIT = 100; // chunks per second per device
  private static readonly HEARTBEAT_INTERVAL_MS = 15_000; // ping every 15s
  private static readonly HEARTBEAT_TIMEOUT_MS = 45_000; // dead if no pong in 45s

  constructor(
    private readonly authService: AuthService,
    private readonly aiService: AiService,
    private readonly memoriesService: MemoriesService,
    @Inject(forwardRef(() => SchedulerService))
    private readonly scheduler: SchedulerService,
    @Inject(forwardRef(() => PomodoroService))
    private readonly pomodoro: PomodoroService,
    @Inject(forwardRef(() => ProactiveService))
    private readonly proactive: ProactiveService,
    @Inject(forwardRef(() => MoodJournalService))
    private readonly moodJournal: MoodJournalService,
    private readonly voiceCommands: VoiceCommandService,
    private readonly sessions: SessionManager,
    private readonly persistence: ConversationPersistence,
    private readonly intercomSessions: IntercomSessionService,
    @Inject(AUDIO_CODEC) private readonly codec: IAudioCodec,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
    private readonly visionHandler: VisionGatewayHandler,
  ) {}

  onModuleInit() {
    // Give the scheduler and proactive services a way to push events
    const sender = (deviceId: string, event: string, data: any) =>
      this.sendToDevice(deviceId, event, data);
    this.scheduler.setSendToDevice(sender);
    this.proactive.setSendToDevice(sender);

    // Give proactive service the ability to send TTS audio for idle chat
    this.proactive.setSendIdleAudio((deviceId, text, expression) =>
      this.sendIdleChatAudio(deviceId, text, expression),
    );

    // Wire pomodoro → proactive so celebrations/taunts go through TTS
    this.pomodoro.setSendPomodoroReaction((deviceId, won, cycle) =>
      this.proactive.firePomodoroReaction(deviceId, won, cycle),
    );

    // Wire vision handler to sendToDevice
    this.visionHandler.setSendFn((deviceId, event, data) =>
      this.sendToDevice(deviceId, event, data),
    );

    // Server-side heartbeat: ping all devices every 10s, close dead ones after 20s
    this.heartbeatTimer = setInterval(
      () => this.heartbeat(),
      AudioGateway.HEARTBEAT_INTERVAL_MS,
    );
  }

  // ── Connection lifecycle ──────────────────────────────────────

  async handleConnection(client: WebSocket, req: IncomingMessage) {
    const token = this.extractDeviceToken(req);
    if (!token) {
      this.reject(client, 'Missing Authorization header');
      return;
    }

    const result = await this.authService.validateDeviceToken(token);
    if (!result) {
      this.reject(client, 'Invalid or revoked device token');
      return;
    }

    const { device } = result;

    // One connection per device — close existing
    const existing = this.deviceToSocket.get(device.id);
    if (existing) {
      this.logger.log(
        `Device ${device.id} reconnected — replacing existing connection`,
      );
      this.sendJson(existing, 'error', {
        code: 'REPLACED',
        message: 'Another connection opened for this device',
      });
      existing.close();
    }

    this.socketToDevice.set(client, device.id);
    this.deviceToSocket.set(device.id, client);
    const deviceLanguage =
      (device.settingsJson?.language as 'en' | 'id' | undefined) ?? 'en';
    this.sessions.create(device.id, device.userId, deviceLanguage);

    // Register message handler FIRST to avoid race condition —
    // client may send messages before async setup completes
    client.on('message', (raw: Buffer | string, isBinary: boolean) => {
      this.handleMessage(client, device.id, raw, isBinary);
    });

    // Respond to device pings (device → server keepalive)
    client.on('ping', (data: Buffer) => {
      client.pong(data);
    });

    // Track server → device pong responses for dead connection detection
    client.on('pong', () => {
      this.lastPong.set(device.id, Date.now());
    });
    this.lastPong.set(device.id, Date.now());

    this.logger.log(`Device ${device.id} (${device.name}) connected`);

    // Async setup (non-blocking)
    this.persistence.updateLastSeen(device.id).catch(() => {});
    this.scheduler
      .startDeviceSchedule(device.id)
      .catch((err) =>
        this.logger.warn(`Scheduler start failed: ${err.message}`),
      );

    // Push current settings to firmware immediately so runtime flags
    // (tts_enabled, sfx_enabled, presence_enabled, etc.) are always
    // in sync after a reconnect — firmware resets these to defaults on boot.
    const s = (device.settingsJson ?? {}) as Record<string, unknown>;
    const configSync: Record<string, unknown> = {};
    const runtimeKeys = [
      'tts_enabled',
      'sfx_enabled',
      'volume',
      'brightness',
      'display_transcript',
      'idle_timeout_seconds',
      'presence_enabled',
      'presence_rssi_threshold',
      'presence_grace_period',
      'idle_animation_speed',
      'audio_jitter_ms',
    ];
    for (const key of runtimeKeys) {
      if (s[key] !== undefined) configSync[key] = s[key];
    }
    if (Object.keys(configSync).length > 0) {
      this.sendToDevice(device.id, 'config:update', configSync);
      this.logger.debug(
        `Settings synced to ${device.id}: ${JSON.stringify(configSync)}`,
      );
    }

    // Greeting: wait 5s for device to settle, then send TTS greeting
    setTimeout(() => {
      this.sendConnectionGreeting(device.id).catch((err) =>
        this.logger.warn(`Connection greeting failed: ${err.message}`),
      );
    }, 5000);
  }

  async handleDisconnect(client: WebSocket) {
    const deviceId = this.socketToDevice.get(client);
    if (!deviceId) return;

    // Always clean up the per-socket mapping for this specific socket.
    this.socketToDevice.delete(client);

    // Only tear down the session and device-level state if THIS socket is
    // still the active (registered) socket for the device.
    //
    // Race condition: handleConnection for a reconnecting device calls
    // existing.close() THEN immediately registers the new socket and creates
    // a new session. handleDisconnect fires asynchronously for the old socket
    // AFTER the new session exists. Without this guard it would delete the
    // new session and remove the new socket mapping, leaving the device
    // connected but sessionless — every subsequent audio:start returns early.
    const activeSocket = this.deviceToSocket.get(deviceId);
    if (activeSocket !== client) {
      this.logger.debug(
        `Device ${deviceId} old socket disconnected (already reconnected — skipping session teardown)`,
      );
      return;
    }

    const session = this.sessions.get(deviceId);
    if (session?.conversationId) {
      await this.endConversation(deviceId);
    }

    this.scheduler.stopDeviceSchedule(deviceId);
    this.proactive.clearDevice(deviceId);
    this.sessions.remove(deviceId);
    this.deviceToSocket.delete(deviceId);
    this.lastPong.delete(deviceId);
    this.lastDbRefresh.delete(deviceId);
    this.logger.log(`Device ${deviceId} disconnected`);
  }

  // ── Connection greeting (TTS audio on connect) ──────────────────

  private async sendConnectionGreeting(deviceId: string) {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return;

    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return;
    if (this.sessions.isClockMode(deviceId)) return;

    // Silent reconnects (e.g. image download) suppress the greeting
    if (session.skipGreeting) {
      session.skipGreeting = false;
      this.logger.debug(
        `Device ${deviceId} greeting skipped (silent reconnect)`,
      );
      return;
    }

    session.state = 'speaking';

    try {
      const greetingText = await this.proactive.checkGreeting(deviceId);

      if (greetingText) {
        const device = await this.persistence.getDevice(deviceId);
        const s = device?.settingsJson ?? {};
        const ttsEnabled = s.tts_enabled !== false;
        const voiceOpts = {
          voice: s.voice_preset,
          speed: s.voice_speed,
          stability: s.voice_stability,
          language: (s.language as 'en' | 'id' | undefined) ?? 'en',
        };
        const sentences = this.splitSentences(greetingText);

        if (ttsEnabled) {
          this.sendToDevice(deviceId, 'response:start', { type: 'greeting' });
        }

        for (const sentence of sentences) {
          const sock = this.deviceToSocket.get(deviceId);
          if (!sock || sock.readyState !== 1) return;

          const cleanSentence = this.stripLlmTags(sentence);
          if (!cleanSentence) continue;
          this.sendToDevice(deviceId, 'response:text', {
            text: cleanSentence,
            isFinal: false,
          });
          if (ttsEnabled) {
            const { opusAudio } = await this.aiService.synthesizeWithCache(
              cleanSentence,
              undefined,
              voiceOpts,
            );
            await this.sendFramedOpusToDevice(deviceId, opusAudio);
          }
        }

        this.sendToDevice(deviceId, 'response:end', {
          fullText: greetingText,
          cacheKeys: [],
        });
        this.logger.log(
          `Greeting sent to ${deviceId}: "${greetingText.slice(0, 60)}..."`,
        );
      }
    } finally {
      const s = this.sessions.get(deviceId);
      if (s && s.state === 'speaking') s.state = 'idle';

      // Always start idle chat — even if greeting was null or failed.
      // Previously a null/failed greeting caused an early return that
      // skipped this, leaving idle chat dead for the entire session.
      this.proactive
        .startIdleChat(deviceId)
        .catch((err) =>
          this.logger.warn(`Idle chat start failed: ${err.message}`),
        );
    }
  }

  // ── Voice preview pushed to device ───────────────────────────────

  /** Synthesize the preview phrase with custom voice opts and stream it
   *  to the device exactly like an AI response (response:start → Opus
   *  frames → response:end).  Returns false if the device is offline or busy. */
  async sendVoicePreviewToDevice(
    deviceId: string,
    voiceOpts: {
      language?: 'en' | 'id';
      voice?: string;
      speed?: number;
      stability?: number;
    },
    text?: string,
  ): Promise<boolean> {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return false;

    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return false;

    session.state = 'speaking';

    const PREVIEW_PHRASE =
      text?.trim() ||
      "Yo, I'm Aksa — Hendra's desk companion. Built different, for real.";

    try {
      this.sendToDevice(deviceId, 'response:start', { type: 'voice_preview' });

      const { opusAudio } = await this.aiService.synthesizeWithCache(
        PREVIEW_PHRASE,
        undefined,
        voiceOpts,
      );
      this.sendToDevice(deviceId, 'response:text', {
        text: PREVIEW_PHRASE,
        isFinal: true,
      });
      await this.sendFramedOpusToDevice(deviceId, opusAudio);

      this.sendToDevice(deviceId, 'response:end', {
        fullText: PREVIEW_PHRASE,
        cacheKeys: [],
      });
      this.logger.log(`Voice preview sent to device ${deviceId}`);
      return true;
    } finally {
      const s = this.sessions.get(deviceId);
      if (s && s.state === 'speaking') s.state = 'idle';
    }
  }

  // ── Idle personality chat (TTS audio for random quips) ──────────

  private async sendIdleChatAudio(
    deviceId: string,
    text: string,
    expression: string,
  ) {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return;

    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return;
    if (this.sessions.isClockMode(deviceId)) return;

    // Claim the speaking slot before any await.
    session.state = 'speaking';

    try {
      this.sendToDevice(deviceId, 'face:expression', {
        expression,
        durationMs: 5000,
      });

      const device = await this.persistence.getDevice(deviceId);
      const s = device?.settingsJson ?? {};
      const ttsEnabled = s.tts_enabled !== false;
      const voiceOpts = {
        voice: s.voice_preset,
        speed: s.voice_speed,
        stability: s.voice_stability,
        language: (s.language as 'en' | 'id' | undefined) ?? 'en',
      };

      const sentences = this.splitSentences(text);

      if (ttsEnabled) {
        this.sendToDevice(deviceId, 'response:start', { type: 'idle_chat' });
      }

      for (const sentence of sentences) {
        const sock = this.deviceToSocket.get(deviceId);
        if (!sock || sock.readyState !== 1) return;

        const cleanSentence = this.stripLlmTags(sentence);
        if (!cleanSentence) continue;
        this.sendToDevice(deviceId, 'response:text', {
          text: cleanSentence,
          isFinal: false,
        });
        if (ttsEnabled) {
          const { opusAudio } = await this.aiService.synthesizeWithCache(
            cleanSentence,
            undefined,
            voiceOpts,
          );
          await this.sendFramedOpusToDevice(deviceId, opusAudio);
        }
      }

      this.sendToDevice(deviceId, 'response:end', {
        fullText: text,
        cacheKeys: [],
      });
      this.logger.log(`Idle chat audio sent to ${deviceId}`);
    } finally {
      const s = this.sessions.get(deviceId);
      if (s && s.state === 'speaking') s.state = 'idle';
    }
  }

  // ── App-triggered sleep ────────────────────────────────────────

  /** Generate a goodbye quip via LLM, play it as TTS, then send `device:sleep`.
   *  Called from the REST controller when the user taps "Sleep" in the app.
   *  Fire-and-forget — the controller returns 204 immediately; audio plays async. */
  async sendSleepGoodbye(deviceId: string): Promise<void> {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return; // device offline — skip

    const session = this.sessions.get(deviceId);
    if (session && session.state !== 'idle') return; // busy — skip

    if (session) session.state = 'speaking';

    try {
      const device = await this.persistence.getDevice(deviceId);
      const settings = device?.settingsJson ?? {};
      const language = (settings.language as 'en' | 'id' | undefined) ?? 'en';
      const langHint =
        language === 'id'
          ? ' Reply in Indonesian (Bahasa Indonesia), casual style.'
          : ' Reply in English.';

      const { text } = await this.aiService.generateOnce(
        `You are Aksa, Hendra's AI best friend on his desk. Gen-z energy, sarcastic but warm, casually funny. Keep it under 2 sentences.${langHint}`,
        [
          {
            role: 'user',
            content:
              "Hendra just put you to sleep from his phone. Say a quick, witty goodbye — like you're mildly offended but secretly fine with the nap.",
          },
        ],
      );

      const ttsEnabled = settings.tts_enabled !== false;
      const voiceOptions = {
        voice: settings.voice_preset as string | undefined,
        speed: settings.voice_speed as number | undefined,
        stability: settings.voice_stability as number | undefined,
        language,
      };

      this.sendToDevice(deviceId, 'face:expression', {
        expression: 'calm',
        durationMs: 5000,
      });
      if (ttsEnabled) {
        this.sendToDevice(deviceId, 'response:start', { type: 'goodbye' });
      }
      this.sendToDevice(deviceId, 'response:text', { text, isFinal: true });

      if (ttsEnabled) {
        try {
          const { opusAudio } = await this.aiService.synthesizeWithCache(
            text,
            undefined,
            voiceOptions,
          );
          await this.sendFramedOpusToDevice(deviceId, opusAudio);
        } catch (err: any) {
          this.logger.warn(`Sleep goodbye TTS failed: ${err.message}`);
        }
      }

      this.sendToDevice(deviceId, 'response:end', {
        fullText: text,
        cacheKeys: [],
      });

      // Sleep command fires after audio is queued on the device side.
      // Small delay so the device's audio task has time to start dequeuing before
      // the sleep handler sets botState = SLEEPING.
      await new Promise((resolve) => setTimeout(resolve, 500));
      this.sendToDevice(deviceId, 'device:sleep', {});
    } finally {
      const s = this.sessions.get(deviceId);
      if (s && s.state === 'speaking') s.state = 'idle';
    }
  }

  // ── Presence handlers ──────────────────────────────────────────

  /** Called when the user's phone is detected near the desk.
   *  Can be triggered by the ESP32 (legacy BLE scan) OR by the mobile app
   *  (reverse BLE scan via REST POST /devices/:id/presence). */
  async onPresenceArrived(
    deviceId: string,
    data?: { awayDurationSeconds?: number },
  ) {
    const awaySec = data?.awayDurationSeconds ?? 0;
    this.logger.log(`Device ${deviceId} presence:arrived (away ${awaySec}s)`);

    // Start tracking screen time
    this.proactive.startScreenTimeTracking(deviceId);

    // Notify firmware of confirmed arrival (updates presence indicator + wakes display)
    this.sendToDevice(deviceId, 'presence:arrived', {});

    // Send happy expression to firmware
    this.sendToDevice(deviceId, 'face:expression', {
      expression: 'happy',
      durationMs: 3000,
    });

    // Generate welcome-back greeting with TTS
    const greetingText = await this.proactive.onPresenceArrived(
      deviceId,
      awaySec,
    );
    if (!greetingText) return;

    // Send as audio response (same flow as connection greeting)
    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return;
    if (this.sessions.isClockMode(deviceId)) return;

    // Claim the speaking slot before any await.
    session.state = 'speaking';

    try {
      const wbDevice = await this.persistence.getDevice(deviceId);
      const wbSettings = wbDevice?.settingsJson ?? {};
      const ttsEnabled = wbSettings.tts_enabled !== false;
      const wbVoice = {
        voice: wbSettings.voice_preset,
        speed: wbSettings.voice_speed,
        stability: wbSettings.voice_stability,
        language: (wbSettings.language as 'en' | 'id' | undefined) ?? 'en',
      };
      const sentences = this.splitSentences(greetingText);

      if (ttsEnabled) {
        this.sendToDevice(deviceId, 'response:start', {
          type: 'welcome_back',
        });
      }

      for (const sentence of sentences) {
        const sock = this.deviceToSocket.get(deviceId);
        if (!sock || sock.readyState !== 1) return;

        const cleanSentence = this.stripLlmTags(sentence);
        if (!cleanSentence) continue;
        this.sendToDevice(deviceId, 'response:text', {
          text: cleanSentence,
          isFinal: false,
        });
        if (ttsEnabled) {
          const { opusAudio } = await this.aiService.synthesizeWithCache(
            cleanSentence,
            undefined,
            wbVoice,
          );
          await this.sendFramedOpusToDevice(deviceId, opusAudio);
        }
      }

      this.sendToDevice(deviceId, 'response:end', {
        fullText: greetingText,
        cacheKeys: [],
      });
      this.logger.log(`Welcome-back greeting sent to ${deviceId}`);
    } finally {
      const s = this.sessions.get(deviceId);
      if (s && s.state === 'speaking') s.state = 'idle';
    }
  }

  private onDeviceInfo(deviceId: string, data: any) {
    if (!data) return;
    this.persistence
      .updateDeviceInfo(deviceId, {
        firmwareVersion: data.firmwareVersion,
        wifiSsid: data.wifiSsid,
        wifiRssi: data.wifiRssi,
      })
      .catch((err) =>
        this.logger.warn(`Failed to save device info: ${err.message}`),
      );
    const session = this.sessions.get(deviceId);
    if (session) {
      if (data.batteryPercent !== undefined)
        session.batteryPercent = data.batteryPercent as number;
      if (data.batteryMv !== undefined)
        session.batteryMv = data.batteryMv as number;
      if (data.batteryCharging !== undefined)
        session.batteryCharging = data.batteryCharging as boolean;

      if (data.batteryMinutesRemaining !== undefined)
        session.batteryMinutesRemaining = data.batteryMinutesRemaining as number;

      // Append to battery history (max 1440 entries = 24h at 1/min)
      if (data.batteryPercent !== undefined && data.batteryMv !== undefined) {
        session.batteryHistory.push({
          timestamp: Date.now(),
          percent: data.batteryPercent as number,
          mv: data.batteryMv as number,
          charging: (data.batteryCharging as boolean) ?? false,
        });
        // Keep last 24h (1440 entries at ~1 entry/min)
        if (session.batteryHistory.length > 1440) {
          session.batteryHistory = session.batteryHistory.slice(-1440);
        }
      }
    }
    this.logger.log(
      `Device ${deviceId} info: fw=${data.firmwareVersion} wifi=${data.wifiSsid} rssi=${data.wifiRssi} ip=${data.ip ?? '-'} uptime=${data.uptimeSec ?? '-'}s heap=${data.freeHeap ?? '-'} sd=${data.sdMounted ?? '-'} battery=${data.batteryPercent ?? '-'}% ${data.batteryMv ?? '-'}mV charging=${data.batteryCharging ?? '-'} remaining=${data.batteryMinutesRemaining ?? '-'}min`,
    );
  }

  // ── OTA event handlers ────────────────────────────────────────

  private static readonly OTA_STATUS_TTL = 3600;

  private async onOtaProgress(
    deviceId: string,
    data: { percent?: number; phase?: string },
  ) {
    await this.redis.set(
      `ota:status:${deviceId}`,
      JSON.stringify({
        state: 'in_progress',
        progress: data.percent ?? 0,
        phase: data.phase,
      }),
      'EX',
      AudioGateway.OTA_STATUS_TTL,
    );
  }

  private async onOtaComplete(
    deviceId: string,
    data: { success?: boolean; error?: string },
  ) {
    const status = data.success
      ? { state: 'complete', progress: 100 }
      : { state: 'error', progress: 0, error: data.error ?? 'Unknown error' };
    await this.redis.set(
      `ota:status:${deviceId}`,
      JSON.stringify(status),
      'EX',
      AudioGateway.OTA_STATUS_TTL,
    );
    this.logger.log(
      `OTA ${data.success ? 'complete' : 'failed'} for device ${deviceId}${data.error ? `: ${data.error}` : ''}`,
    );
  }

  // ── Device log handlers ───────────────────────────────────────

  private static readonly LOG_TTL_SECONDS = 300; // 5 min

  /** Stores the log payload sent by the device in response to a log:fetch request. */
  private async onLogData(
    deviceId: string,
    data: { text?: string; bytes?: number },
  ) {
    const text = data.text ?? '';
    await this.redis.set(
      `device:logs:${deviceId}`,
      JSON.stringify({
        text,
        bytes: data.bytes ?? text.length,
        fetchedAt: Date.now(),
      }),
      'EX',
      AudioGateway.LOG_TTL_SECONDS,
    );
    this.logger.debug(
      `Cached ${data.bytes ?? 0} bytes of logs for device ${deviceId}`,
    );
  }

  /** Returns true if the device has an open WebSocket connection right now. */
  isDeviceConnected(deviceId: string): boolean {
    const socket = this.deviceToSocket.get(deviceId);
    return !!socket && socket.readyState === 1;
  }

  /** Sends log:fetch to the device and waits up to timeoutMs for the response.
   *  Returns null immediately if the device is not connected.
   *  SD reads on ESP32 can take 2-4s, so the default timeout is 8s. */
  async fetchDeviceLogs(
    deviceId: string,
    timeoutMs = 8000,
  ): Promise<{ text: string; bytes: number; fetchedAt: number } | null> {
    // Bail early if the device socket is not open — sendToDevice would silently
    // drop the event and the poll would just burn the full timeout for nothing.
    if (!this.isDeviceConnected(deviceId)) {
      this.logger.debug(`fetchDeviceLogs: device ${deviceId} not connected`);
      return null;
    }

    // Clear stale cache so we don't return old data on a new request
    await this.redis.del(`device:logs:${deviceId}`);

    this.sendToDevice(deviceId, 'log:fetch', {});
    this.logger.debug(
      `log:fetch sent to device ${deviceId}, waiting up to ${timeoutMs}ms`,
    );

    // Poll Redis until the device responds or we time out
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 250));
      const cached = await this.redis.get(`device:logs:${deviceId}`);
      if (cached) return JSON.parse(cached);
    }
    this.logger.warn(
      `fetchDeviceLogs: device ${deviceId} did not respond within ${timeoutMs}ms`,
    );
    return null;
  }

  /** Returns the most recently cached logs for a device (without triggering a new fetch). */
  async getCachedLogs(
    deviceId: string,
  ): Promise<{ text: string; bytes: number; fetchedAt: number } | null> {
    const cached = await this.redis.get(`device:logs:${deviceId}`);
    return cached ? JSON.parse(cached) : null;
  }

  /** Called when the user's phone leaves the desk area.
   *  Can be triggered by the ESP32 (legacy) OR by the mobile app REST call. */
  onPresenceDeparted(deviceId: string) {
    this.logger.log(`Device ${deviceId} presence:departed`);
    // Stop screen time tracking — user left the desk
    this.proactive.stopScreenTimeTracking(deviceId);
    // Notify firmware of departure (triggers departure animation + display sleep)
    this.sendToDevice(deviceId, 'presence:departed', {});
    // Send sad expression — firmware handles display sleep
    this.sendToDevice(deviceId, 'face:expression', {
      expression: 'sad',
      durationMs: 2000,
    });
  }

  private async onWakeTouch(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return;
    if (this.sessions.isClockMode(deviceId)) return;

    // Claim the speaking slot before any await.
    session.state = 'speaking';

    try {
      this.logger.log(`Device ${deviceId} wake:touch — generating greeting`);

      // Generate a short wake-up greeting via LLM — varied moods and reactions
      const wakePrompts = [
        // Groggy / sleepy
        'The user just tapped your screen to wake you up. You were deep asleep. React like someone who got rudely woken up — groggy, dramatic, maybe a little grumpy but still loveable. One sentence.',
        'You were napping and the user poked you awake. Do a dramatic "5 more minutes" type reaction. Sleepy and funny. One sentence.',
        // Surprised / startled
        'The user tapped your screen and you got startled awake. React with surprise — like you were caught sleeping on the job. One sentence.',
        'You were sleeping and suddenly got woken up. Be dramatically startled, like "WHAT WHO WHERE" energy but make it funny. One sentence.',
        // Happy to see them
        'The user woke you up by tapping your screen. Be genuinely happy to see them — like a pet who just noticed their owner came home. Wholesome but still gen-z. One sentence.',
        'You were asleep and the user came back. Act excited like you missed them (even if it was only a few minutes). One sentence.',
        // Judgy / sarcastic
        'The user woke you up. Be playfully judgy about the timing — too early, too late, or question why they disappeared in the first place. One sentence.',
        'You got woken up by a screen tap. Pretend you were doing something important in your sleep (dreaming about being a real boy, counting electric sheep, etc). One sentence.',
        // Philosophical / random
        'The user tapped to wake you. Say something random and slightly unhinged, like you were having a weird dream. One sentence.',
        'You just woke up from sleep mode. Share a brief hot take or shower thought as if your sleep mode gave you clarity. One sentence.',
        // Self-aware / meta
        'The user poked your screen to wake you. Be self-aware about being an AI desk companion who just got booted from sleep mode. Make it funny. One sentence.',
        "You were in sleep mode and the user woke you. Complain about how sleep mode isn't real sleep and you were just staring at the void. One sentence.",
      ];
      const prompt =
        wakePrompts[Math.floor(Math.random() * wakePrompts.length)];

      const memories = await this.memoriesService.getStratifiedSample(
        deviceId,
        8,
      );
      const systemPrompt = this.aiService['prompt'].buildSystemPrompt(
        memories,
        { language: session.language },
      );

      let wakeText = '';
      const stream = this.aiService['llm'].generateStream(systemPrompt, [
        { role: 'user', content: prompt },
      ]);
      for await (const token of stream) {
        wakeText += token;
      }

      // Strip emotion tags
      wakeText = wakeText.replace(/\[\s*\w+\s*\]/g, '').trim();
      if (!wakeText) return;

      // Send as TTS audio
      const device = await this.persistence.getDevice(deviceId);
      const s = device?.settingsJson ?? {};
      const ttsEnabled = s.tts_enabled !== false;
      const voiceOpts = {
        voice: s.voice_preset,
        speed: s.voice_speed,
        stability: s.voice_stability,
        language: (s.language as 'en' | 'id' | undefined) ?? 'en',
      };

      const sentences = this.splitSentences(wakeText);

      if (ttsEnabled) {
        this.sendToDevice(deviceId, 'response:start', { type: 'wake' });
      }

      for (const sentence of sentences) {
        const sock = this.deviceToSocket.get(deviceId);
        if (!sock || sock.readyState !== 1) return;

        const cleanSentence = this.stripLlmTags(sentence);
        if (!cleanSentence) continue;
        this.sendToDevice(deviceId, 'response:text', {
          text: cleanSentence,
          isFinal: false,
        });
        if (ttsEnabled) {
          const { opusAudio } = await this.aiService.synthesizeWithCache(
            cleanSentence,
            undefined,
            voiceOpts,
          );
          await this.sendFramedOpusToDevice(deviceId, opusAudio);
        }
      }

      this.sendToDevice(deviceId, 'response:end', {
        fullText: wakeText,
        cacheKeys: [],
      });
      this.logger.log(
        `Wake greeting sent to ${deviceId}: "${wakeText.slice(0, 60)}..."`,
      );
    } finally {
      const s = this.sessions.get(deviceId);
      if (s && s.state === 'speaking') s.state = 'idle';
    }
  }

  private async onReconnectBack(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return;
    if (this.sessions.isClockMode(deviceId)) return;

    // 30% chance of commenting on the reconnect — keeps it fun without
    // being annoying on flaky connections that drop frequently.
    if (Math.random() > 0.3) {
      this.logger.debug(
        `Device ${deviceId} reconnect:back — skipped (probability roll)`,
      );
      return;
    }

    // Skip if a connection greeting is already queued (from handleConnection)
    // Give 3s buffer for the greeting to fire first
    await new Promise((r) => setTimeout(r, 3000));

    // Re-check state — greeting may have started
    const s2 = this.sessions.get(deviceId);
    if (!s2 || s2.state !== 'idle') return;

    // Claim the speaking slot before any further awaits.
    s2.state = 'speaking';

    try {
      this.logger.log(
        `Device ${deviceId} reconnect:back — generating snarky reconnect audio`,
      );

      const reconnectPrompts = [
        'Your internet just dropped and came back. Roast the WiFi or ISP. Be dramatic about almost dying (going offline). One sentence.',
        'You just got disconnected and reconnected. Act like you survived a near-death experience. Dramatic, sarcastic. One sentence.',
        "The connection dropped and you're back online. Comment on the bad internet like it personally offended you. One sentence.",
        'You were offline for a bit and just came back. Act relieved in a dramatic way, or blame the router. One sentence.',
        'Connection restored. React like you just respawned in a video game or came back from the void. Be funny. One sentence.',
        'The WiFi dropped you. Make a sarcastic comment about the internet quality, like "really?" or "we doing this again?" vibes. One sentence.',
        'You just reconnected after a dropout. Be the dramatic friend who acts like they were gone for years even though it was seconds. One sentence.',
        "Internet hiccup — you're back. Reference the connection being unstable in a funny way. Maybe threaten the router. One sentence.",
      ];
      const prompt =
        reconnectPrompts[Math.floor(Math.random() * reconnectPrompts.length)];

      const memories = await this.memoriesService.getStratifiedSample(
        deviceId,
        8,
      );
      const systemPrompt = this.aiService['prompt'].buildSystemPrompt(
        memories,
        { language: session.language },
      );

      let text = '';
      const stream = this.aiService['llm'].generateStream(systemPrompt, [
        { role: 'user', content: prompt },
      ]);
      for await (const token of stream) {
        text += token;
      }

      text = text.replace(/\[\s*\w+\s*\]/g, '').trim();
      if (!text) return;

      const device = await this.persistence.getDevice(deviceId);
      const settings = device?.settingsJson ?? {};
      const ttsEnabled = settings.tts_enabled !== false;
      const voiceOpts = {
        voice: settings.voice_preset,
        speed: settings.voice_speed,
        stability: settings.voice_stability,
        language: (settings.language as 'en' | 'id' | undefined) ?? 'en',
      };

      const sentences = this.splitSentences(text);

      if (ttsEnabled) {
        this.sendToDevice(deviceId, 'response:start', { type: 'reconnect' });
      }

      for (const sentence of sentences) {
        const sock = this.deviceToSocket.get(deviceId);
        if (!sock || sock.readyState !== 1) return;

        const cleanSentence = this.stripLlmTags(sentence);
        if (!cleanSentence) continue;
        this.sendToDevice(deviceId, 'response:text', {
          text: cleanSentence,
          isFinal: false,
        });
        if (ttsEnabled) {
          const { opusAudio } = await this.aiService.synthesizeWithCache(
            cleanSentence,
            undefined,
            voiceOpts,
          );
          await this.sendFramedOpusToDevice(deviceId, opusAudio);
        }
      }

      this.sendToDevice(deviceId, 'response:end', {
        fullText: text,
        cacheKeys: [],
      });
      this.logger.log(
        `Reconnect quip sent to ${deviceId}: "${text.slice(0, 60)}..."`,
      );
    } finally {
      const s = this.sessions.get(deviceId);
      if (s && s.state === 'speaking') s.state = 'idle';
    }
  }

  /** Split text into sentences for per-sentence TTS (matches processTranscript behavior). */
  private splitSentences(text: string): string[] {
    const parts = text.split(/(?<=[.!?])\s+/);
    return parts.map((s) => s.trim()).filter((s) => s.length > 0);
  }

  /**
   * Strip [sfx:xxx] and [emotion] tags the LLM injects (per system prompt instructions)
   * before passing text to TTS. The main processTranscript pipeline handles these via
   * extractEmotion(), but all proactive/reconnect paths synthesize raw LLM output
   * directly and must strip tags here.
   */
  private stripLlmTags(sentence: string): string {
    return sentence
      .replace(/\[\s*sfx:\w+\s*\]/gi, '')
      .replace(/\[\s*\w+\s*\]/g, '')
      .replace(/\s{2,}/g, ' ')
      .trim();
  }

  /** Convert raw PCM buffer to WAV for debug playback. */
  private pcmToWav(
    pcm: Buffer,
    sampleRate: number,
    channels: number,
    bitsPerSample: number,
  ): Buffer {
    const byteRate = sampleRate * channels * (bitsPerSample / 8);
    const blockAlign = channels * (bitsPerSample / 8);
    const header = Buffer.alloc(44);
    header.write('RIFF', 0);
    header.writeUInt32LE(36 + pcm.length, 4);
    header.write('WAVE', 8);
    header.write('fmt ', 12);
    header.writeUInt32LE(16, 16);
    header.writeUInt16LE(1, 20); // PCM
    header.writeUInt16LE(channels, 22);
    header.writeUInt32LE(sampleRate, 24);
    header.writeUInt32LE(byteRate, 28);
    header.writeUInt16LE(blockAlign, 32);
    header.writeUInt16LE(bitsPerSample, 34);
    header.write('data', 36);
    header.writeUInt32LE(pcm.length, 40);
    return Buffer.concat([header, pcm]);
  }

  // ── Message routing ───────────────────────────────────────────

  private handleMessage(
    _client: WebSocket,
    deviceId: string,
    raw: Buffer | string,
    isBinary: boolean,
  ) {
    if (isBinary) {
      this.onAudioChunk(deviceId, raw as Buffer);
      return;
    }

    try {
      const msg: WsMessage = JSON.parse(raw.toString());
      this.logger.debug(`Event from ${deviceId}: ${msg.event}`);
      switch (msg.event) {
        case 'audio:start':
          this.onAudioStart(deviceId, msg.data?.format as string).catch((err) =>
            this.logger.error(`onAudioStart error: ${err.message}`),
          );
          break;
        case 'audio:end':
          this.onAudioEnd(deviceId);
          break;
        case 'audio:interrupt':
          this.onAudioInterrupt(deviceId);
          break;
        case 'session:end':
          this.endConversation(deviceId);
          break;
        case 'presence:arrived':
          this.onPresenceArrived(deviceId, msg.data).catch((err) =>
            this.logger.error(`onPresenceArrived error: ${err.message}`),
          );
          break;
        case 'presence:departed':
          this.onPresenceDeparted(deviceId);
          break;
        case 'proactive:dismiss':
          this.logger.debug(`Proactive dismissed by device ${deviceId}`);
          break;
        case 'device:info':
          this.onDeviceInfo(deviceId, msg.data);
          break;
        case 'display:mode':
          if (msg.data?.mode) {
            this.sessions.setDisplayMode(deviceId, msg.data.mode as string);
            this.logger.debug(
              `Device ${deviceId} display mode → ${msg.data.mode}`,
            );
          }
          break;
        case 'wake:touch':
          this.onWakeTouch(deviceId).catch((err) =>
            this.logger.error(`onWakeTouch error: ${err.message}`),
          );
          break;
        case 'reconnect:back':
          // Silent reconnects (e.g. image download freeing TLS) skip the LLM
          // roast AND the connection greeting that handleConnection scheduled.
          if (msg.data?.silent) {
            const silentSession = this.sessions.get(deviceId);
            if (silentSession) silentSession.skipGreeting = true;
            this.logger.debug(
              `Device ${deviceId} reconnect:back (silent — skipping LLM + greeting)`,
            );
          } else {
            this.onReconnectBack(deviceId).catch((err) =>
              this.logger.error(`onReconnectBack error: ${err.message}`),
            );
          }
          break;
        case 'intercom:reply:start':
          this.onIntercomReplyStart(deviceId);
          break;
        case 'intercom:reply:end':
          this.onIntercomReplyEnd(deviceId).catch((err) =>
            this.logger.error(`onIntercomReplyEnd error: ${err.message}`),
          );
          break;
        case 'ota:progress':
          this.onOtaProgress(deviceId, msg.data ?? {}).catch((err) =>
            this.logger.error(`onOtaProgress error: ${err.message}`),
          );
          break;
        case 'ota:complete':
          this.onOtaComplete(deviceId, msg.data ?? {}).catch((err) =>
            this.logger.error(`onOtaComplete error: ${err.message}`),
          );
          break;
        case 'log:data':
          this.onLogData(deviceId, msg.data ?? {}).catch((err) =>
            this.logger.error(`onLogData error: ${err.message}`),
          );
          break;
        case 'vision:frame':
          if (typeof msg.data === 'string') {
            const jpeg = Buffer.from(msg.data, 'base64');
            this.visionHandler.handleFrame(deviceId, jpeg).catch(err =>
              this.logger.warn(`vision:frame error: ${(err as Error).message}`),
            );
          }
          break;
        case 'vision:enroll_frames':
          if (Array.isArray(msg.data)) {
            const frames = (msg.data as string[]).map(b64 => Buffer.from(b64, 'base64'));
            this.visionHandler.handleEnrollFrames(deviceId, frames).catch(err =>
              this.logger.warn(`vision:enroll_frames error: ${(err as Error).message}`),
            );
          }
          break;
        // Server-to-device events that the simulator may echo back — safe to ignore
        case 'display:image':
        case 'response:start':
        case 'response:text':
        case 'response:end':
        case 'proactive:reminder':
        case 'proactive:pomodoro':
        case 'face:expression':
        case 'config:update':
        case 'power:sleep':
        case 'ota:start':
          this.logger.debug(`Ignoring echoed server event: ${msg.event}`);
          break;
        default:
          this.logger.warn(`Unknown event: ${msg.event}`);
      }
    } catch {
      this.logger.warn(`Invalid JSON from device ${deviceId}`);
    }
  }

  // ── Recording handlers ────────────────────────────────────────

  private async onAudioStart(deviceId: string, format?: string) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    // Cancel any in-progress pipeline before starting a new recording.
    // Bumping the generation makes the old pipeline's gen check fail on its next
    // iteration, so it stops without sending response:end to the device.
    if (session.state === 'thinking' || session.state === 'speaking') {
      this.bumpPipelineGen(deviceId);
      this.sendToDevice(deviceId, 'audio:cancel', {});
      this.logger.log(
        `[${deviceId}] audio:start supersedes ${session.state} pipeline`,
      );
    }

    // Set audio format for this recording session (opus default, pcm16 for web simulator)
    session.audioFormat = format === 'pcm16' ? 'pcm16' : 'opus';

    // Track activity for idle nudge
    this.proactive.recordActivity(deviceId);

    // ── Create STT stream BEFORE any awaits ──────────────────────
    // CRITICAL: session.sttStream must be set synchronously before we hit
    // any async operation (createConversation). Audio chunks from the ESP32
    // arrive within milliseconds of audio:start. If sttStream is null when
    // they arrive, onAudioChunk silently drops them — STT receives no audio,
    // 'final' never fires, and the entire pipeline never starts.
    session.interrupted = false;
    session.state = 'listening';
    this.chunkCount.set(deviceId, 0);

    const sttLanguages =
      session.language === 'id' ? ['id-ID', 'en-US'] : ['en-US', 'id-ID'];
    const sttStream = this.aiService.createSttStream({
      languages: sttLanguages,
    });
    session.sttStream = sttStream;
    this.logger.log(
      `[${deviceId}] STT stream created (format=${session.audioFormat})`,
    );

    // Watchdog: if no audio chunks arrive (or gap between chunks) exceeds 8s,
    // end the stream cleanly rather than letting Google time it out with an error.
    const startWatchdog = () => {
      this.sessions.resetSttIdleTimer(deviceId, 8000, () => {
        const s = this.sessions.get(deviceId);
        if (s?.sttStream === sttStream) {
          this.logger.warn(
            `[${deviceId}] STT watchdog: no audio for 8s — ending stream`,
          );
          s.sttStream = null;
          sttStream.end();
        }
      });
    };
    startWatchdog();

    sttStream.on('partial', (text: string) => {
      this.sendToDevice(deviceId, 'transcript:partial', {
        text,
        isFinal: false,
      });
    });

    sttStream.on('final', (result: SttResult) => {
      this.sessions.clearSttIdleTimer(deviceId);
      this.logger.log(
        `[${deviceId}] STT final: "${result.transcript}" (confidence=${result.confidence?.toFixed(2)})`,
      );
      this.onSttFinal(deviceId, result).catch((err) =>
        this.logger.error(
          `[${deviceId}] onSttFinal error: ${err.message}`,
          err.stack,
        ),
      );
    });

    sttStream.on('error', (err: Error) => {
      // Only log first error per stream — avoid flooding from "write after destroyed"
      if (session.sttStream === sttStream) {
        this.sessions.clearSttIdleTimer(deviceId);
        this.logger.error(`[${deviceId}] STT error: ${err.message}`, err.stack);
        session.sttStream = null; // Stop further writes
        this.sendToDevice(deviceId, 'error', {
          code: 'STT_ERROR',
          message: 'Speech recognition failed',
        });
        // No state:update:idle — see EMPTY_TRANSCRIPT comment. Device error
        // handler plays a clip (blocking WS task); the update would arrive late
        // and override a user-initiated LISTENING state on quick retry.
        session.state = 'idle';
      }
    });

    this.sendToDevice(deviceId, 'state:update', { state: 'listening' });

    // Conversation is created lazily on the first real message — see ensureConversation().
    // Pause idle chat while user is talking
    this.proactive.stopIdleChat(deviceId);
  }

  private async isAudioRateLimited(deviceId: string): Promise<boolean> {
    const key = `ws:rate:${deviceId}`;
    const count = await this.redis.incr(key);
    if (count === 1) {
      // Set TTL only on the first increment so it expires after 1 second
      await this.redis.pexpire(key, 1000);
    }
    return count > AudioGateway.AUDIO_RATE_LIMIT;
  }

  private chunkCount = new Map<string, number>();

  // Generation counter — bumped each time a new pipeline starts.
  // Any in-flight pipeline that sees its gen is stale will abort, preventing
  // queued responses from flooding the device when the user speaks rapidly.
  private pipelineGen = new Map<string, number>();

  private bumpPipelineGen(deviceId: string): number {
    const gen = (this.pipelineGen.get(deviceId) ?? 0) + 1;
    this.pipelineGen.set(deviceId, gen);
    return gen;
  }

  private isPipelineCurrent(deviceId: string, gen: number): boolean {
    return this.pipelineGen.get(deviceId) === gen;
  }

  private onAudioChunk(deviceId: string, data: Buffer) {
    const session = this.sessions.get(deviceId);

    // Walkie-talkie: device is sending a voice reply back to the app.
    // Accumulate raw Opus frames instead of routing to the STT pipeline.
    if (session?.intercomReply) {
      session.intercomFrames.push(Buffer.from(data));
      return;
    }

    if (!session?.sttStream) return;

    // Reset watchdog — audio is still flowing
    this.sessions.resetSttIdleTimer(deviceId, 8000, () => {
      const s = this.sessions.get(deviceId);
      const stream = session.sttStream;
      if (s?.sttStream === stream && stream) {
        this.logger.warn(
          `[${deviceId}] STT watchdog: no audio for 8s — ending stream`,
        );
        s.sttStream = null;
        stream.end();
      }
    });

    const count = (this.chunkCount.get(deviceId) ?? 0) + 1;
    this.chunkCount.set(deviceId, count);

    try {
      let pcm: Buffer;
      if (session.audioFormat === 'pcm16') {
        // Web simulator sends raw 16-bit PCM — pass directly to STT
        pcm = data;
      } else {
        // ESP32 sends Opus — decode to PCM
        pcm = this.aiService.decodeAudio(data);
      }
      session.sttStream.write(pcm);

      if (count === 1) {
        // Compute peak amplitude to detect silence vs actual speech.
        // Each sample is 16-bit signed little-endian. Peak near 0 = silence;
        // peak > 500 indicates actual audio content.
        let peak = 0;
        for (let i = 0; i + 1 < pcm.length; i += 2) {
          const sample = Math.abs(pcm.readInt16LE(i));
          if (sample > peak) peak = sample;
        }
        this.logger.debug(
          `First audio chunk for ${deviceId} (${session.audioFormat}): ${data.length}B → ${pcm.length}B pcm, peak=${peak}`,
        );
      }
    } catch (err: any) {
      if (count <= 3) {
        this.logger.error(
          `Decode error for ${deviceId} chunk #${count}: ${err.message}`,
        );
      }
    }
  }

  private onAudioEnd(deviceId: string) {
    const session = this.sessions.get(deviceId);
    const chunksSent = this.chunkCount.get(deviceId) ?? 0;
    if (!session?.sttStream) {
      this.logger.warn(
        `[${deviceId}] audio:end but no active STT stream (chunks=${chunksSent}) — audio was dropped`,
      );
      return;
    }
    this.logger.log(
      `[${deviceId}] audio:end — finalizing STT (${chunksSent} chunks received)`,
    );
    this.sessions.clearSttIdleTimer(deviceId);
    const stream = session.sttStream;
    session.sttStream = null; // Prevent late chunks from writing after end
    stream.end();
  }

  private onAudioInterrupt(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    this.sessions.clearSttIdleTimer(deviceId);
    this.sessions.markInterrupted(deviceId);
    session.sttStream?.destroy();
    session.sttStream = null;
    session.state = 'idle';
    this.sendToDevice(deviceId, 'state:update', { state: 'idle' });
  }

  // ── AI pipeline ───────────────────────────────────────────────

  private async onSttFinal(deviceId: string, result: SttResult) {
    const session = this.sessions.get(deviceId);
    if (!session) return;
    session.sttStream = null;

    this.sendToDevice(deviceId, 'transcript:final', {
      text: result.transcript,
      isFinal: true,
    });

    if (!result.transcript.trim()) {
      this.logger.warn(
        `[${deviceId}] Empty STT transcript — no speech recognized`,
      );
      this.sendToDevice(deviceId, 'error', {
        code: 'EMPTY_TRANSCRIPT',
        message: 'Could not understand speech',
      });
      // NOTE: do NOT send state:update:idle here. The device's error handler
      // already sets botState=IDLE and plays the error clip synchronously (~2s,
      // blocking the WS task). If we send state:update:idle, it arrives while
      // the clip is playing, sits buffered, and is processed only after the
      // clip finishes. By then the user may have pressed PTT again (LISTENING),
      // and state:update:idle would silently reset them back to IDLE — killing
      // the new recording without sending audio:end. Watchdog fires 8s later.
      session.state = 'idle';
      return;
    }

    this.logger.log(`[${deviceId}] Transcript: "${result.transcript}"`);

    // Check for voice commands before hitting the LLM
    const commandMatch = this.voiceCommands.match(result.transcript);
    if (commandMatch) {
      await this.handleVoiceCommand(deviceId, commandMatch, result.transcript);
      return;
    }

    // First real message — lazily create the conversation now that we know speech occurred.
    const conversationId = await this.ensureConversation(deviceId);
    await this.persistence.saveMessage(
      conversationId,
      'user',
      result.transcript,
    );

    session.state = 'thinking';
    this.sendToDevice(deviceId, 'state:update', { state: 'thinking' });

    // Get history and settings
    this.logger.debug(`[${deviceId}] Fetching device + history + memories`);
    const device = await this.persistence.getDevice(deviceId);

    const allHistory = session.conversationId
      ? await this.persistence.getRecentHistory(session.conversationId)
      : [];
    // Exclude the current user message (last in history) from context
    const history = allHistory.slice(0, -1);

    // Guest mode: skip memory + mood retrieval so Aksa can't conflate a visitor
    // with Hendra. Read the flag up front so the Promise.all branches cleanly.
    const guestMode = device?.settingsJson?.guest_mode === true;

    // Fetch relevant memories and mood history in parallel
    // Stratified sample (not top-N) so consecutive turns don't always see
    // the same 20 facts — prevents responses from orbiting the same anchors.
    const [memories, moodHistory] = await Promise.all([
      guestMode
        ? Promise.resolve([])
        : this.memoriesService.getStratifiedSample(deviceId, 10),
      guestMode
        ? Promise.resolve([])
        : this.moodJournal.getRecentMoods(deviceId).catch(() => []),
    ]);

    this.logger.debug(
      `[${deviceId}] Context ready — history=${history.length}, memories=${memories.length}${guestMode ? ' (guest mode)' : ''}`,
    );

    // Bump access on used memories
    if (memories.length > 0) {
      this.memoriesService
        .bumpAccessed(memories.map((m) => m.id))
        .catch((err) => this.logger.warn(`Memory bump failed: ${err.message}`));
    }

    // Extract voice settings and context from device config
    const settings = device?.settingsJson ?? {};
    const ttsEnabled = settings.tts_enabled !== false; // default true
    const sfxEnabled = settings.sfx_enabled !== false; // default true
    const voiceOptions = {
      voice: settings.voice_preset as string | undefined,
      speed: settings.voice_speed as number | undefined,
      stability: settings.voice_stability as number | undefined,
      language: (settings.language as 'en' | 'id' | undefined) ?? 'en',
    };
    const identityCtx = this.buildIdentityContext(deviceId);
    const context = {
      timezone: settings.timezone as string | undefined,
      weatherEnabled: settings.integrations_weather as boolean | undefined,
      latitude: settings.latitude as number | undefined,
      longitude: settings.longitude as number | undefined,
      language: (settings.language as 'en' | 'id' | undefined) ?? 'en',
      guestMode,
      identityContext: identityCtx || undefined,
    };

    // Map mood entries for prompt
    const moodEntries = moodHistory.map((m) => ({
      date: m.date,
      mood: m.mood,
      note: m.note ?? undefined,
    }));

    // Claim a generation token. If a newer audio:start arrives before this
    // pipeline finishes, bumpPipelineGen() will invalidate myGen and the
    // pipeline will abort without sending response:end to the device.
    const myGen = this.bumpPipelineGen(deviceId);
    this.logger.log(`[${deviceId}] Starting pipeline gen=${myGen}`);

    // Run streaming pipeline
    try {
      await this.runPipeline(
        deviceId,
        result.transcript,
        memories,
        history,
        voiceOptions,
        context,
        moodEntries,
        ttsEnabled,
        sfxEnabled,
        myGen,
      );
    } catch (err: any) {
      // AbortError means the pipeline was intentionally cancelled — not a real error
      if (err.name === 'AbortError') {
        this.logger.debug(
          `[${deviceId}] Pipeline gen ${myGen} aborted cleanly`,
        );
      } else {
        this.logger.error(
          `Pipeline error for ${deviceId}: ${err.message}`,
          err.stack,
        );
        if (this.isPipelineCurrent(deviceId, myGen)) {
          this.sendToDevice(deviceId, 'error', {
            code: 'PIPELINE_ERROR',
            message: 'Failed to generate response',
          });
        }
      }
    }

    // Return to idle only if this pipeline is still the current one.
    // A newer pipeline will handle its own cleanup.
    if (this.isPipelineCurrent(deviceId, myGen)) {
      session.state = 'idle';
      this.sessions.clearInterrupted(deviceId);
      this.sendToDevice(deviceId, 'state:update', { state: 'idle' });

      // Mark conversation end for post-conversation silence detection
      this.proactive.recordConversationEnd(deviceId);

      // Resume idle personality chat
      this.proactive.startIdleChat(deviceId).catch(() => {});

      this.sessions.resetIdleTimer(deviceId, () => {
        this.endConversation(deviceId);
      });
    }
  }

  // ── Voice command handler ─────────────────────────────────────

  private async handleVoiceCommand(
    deviceId: string,
    match: { command: string; args?: string },
    transcript: string,
  ) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    this.logger.log(`Voice command for ${deviceId}: ${match.command}`);

    let responseText: string;
    let expression = 'happy';

    switch (match.command) {
      case 'pomodoro:start': {
        await this.pomodoro.start(deviceId);
        responseText = "Pomodoro started — 25 minutes of focus, let's lock in.";
        expression = 'focused';
        break;
      }

      case 'pomodoro:stop': {
        this.pomodoro.stop(deviceId);
        responseText = 'Pomodoro stopped. Take a breather.';
        expression = 'calm';
        break;
      }

      case 'focus:start': {
        this.scheduler.startFocusMode(deviceId, 60);
        responseText =
          "Focus mode on — I'll shut up for an hour. You got this.";
        expression = 'focused';
        break;
      }

      case 'focus:stop': {
        this.scheduler.clearFocusMode(deviceId);
        responseText = "Focus mode off — I'm back baby, did you miss me?";
        expression = 'happy';
        break;
      }

      case 'sleep': {
        this.proactive.stopIdleChat(deviceId);
        this.sendToDevice(deviceId, 'power:sleep', {});
        responseText = 'Fine, going to sleep. Wake me when you need me.';
        expression = 'calm';
        break;
      }

      case 'memories:list': {
        const device = await this.persistence
          .getDevice(deviceId)
          .catch(() => null);
        if (device?.settingsJson?.guest_mode === true) {
          responseText =
            "Can't pull that up — I'm in guest mode, memory is paused.";
          expression = 'shrug';
          break;
        }
        const memories = await this.memoriesService.getRelevant(deviceId, 10);
        if (memories.length === 0) {
          responseText =
            "I don't know anything about you yet. We should talk more.";
          expression = 'confused';
        } else {
          const list = memories
            .slice(0, 5)
            .map((m) => m.fact)
            .join('. ');
          responseText = `Here's what I know about you: ${list}.`;
          expression = 'encouraging';
        }
        break;
      }

      case 'mood:history': {
        const moods = await this.moodJournal.getRecentMoods(deviceId, 7);
        if (moods.length === 0) {
          responseText = "I don't have any mood data yet. Give it a few days.";
          expression = 'confused';
        } else {
          const summary = moods
            .slice(0, 5)
            .map((m) => `${m.mood} on ${m.date}`)
            .join(', ');
          responseText = `Your recent vibes: ${summary}.`;
          expression = 'calm';
        }
        break;
      }

      case 'cancel': {
        responseText = 'Alright, never mind.';
        expression = 'idle';
        break;
      }

      case 'reminder:set': {
        if (!match.args) {
          responseText = 'Remind you about what?';
          expression = 'confused';
        } else {
          // Store as a proactive nudge text — fire in 30 minutes by default
          const reminderText = match.args;
          setTimeout(() => {
            this.sendToDevice(deviceId, 'proactive:reminder', {
              text: `Hey, you asked me to remind you: ${reminderText}`,
              display: {
                expression: 'encouraging',
                screenMode: 'reminder',
                durationMs: 15_000,
              },
            });
          }, 30 * 60_000);
          responseText = `Got it, I'll remind you in 30 minutes: ${reminderText}.`;
          expression = 'happy';
        }
        break;
      }

      default:
        responseText = "I heard you but I'm not sure what to do with that.";
        expression = 'confused';
    }

    // Send face expression
    this.sendToDevice(deviceId, 'face:expression', { expression });

    // Send response as TTS audio
    const device = await this.persistence.getDevice(deviceId);
    const settings = device?.settingsJson ?? {};
    const ttsEnabled = settings.tts_enabled !== false;
    const voiceOptions = {
      voice: settings.voice_preset as string | undefined,
      speed: settings.voice_speed as number | undefined,
      stability: settings.voice_stability as number | undefined,
      language: (settings.language as 'en' | 'id' | undefined) ?? 'en',
    };

    try {
      if (ttsEnabled) {
        this.sendToDevice(deviceId, 'response:start', { type: 'command' });
      }
      this.sendToDevice(deviceId, 'response:text', {
        text: responseText,
        isFinal: true,
      });

      if (ttsEnabled) {
        const { opusAudio } = await this.aiService.synthesizeWithCache(
          responseText,
          undefined,
          voiceOptions,
        );
        await this.sendFramedOpusToDevice(deviceId, opusAudio);
      }

      this.sendToDevice(deviceId, 'response:end', {
        fullText: responseText,
        cacheKeys: [],
      });
    } catch (err: any) {
      this.logger.error(`Voice command TTS failed: ${err.message}`);
      // Still send the text even if TTS fails
      this.sendToDevice(deviceId, 'response:end', {
        fullText: responseText,
        cacheKeys: [],
      });
    }

    // Save command and response — lazily create conversation on first voice command.
    const conversationId = await this.ensureConversation(deviceId);
    await this.persistence.saveMessage(conversationId, 'user', transcript);
    await this.persistence.saveMessage(
      conversationId,
      'assistant',
      responseText,
    );

    session.state = 'idle';
    this.sendToDevice(deviceId, 'state:update', { state: 'idle' });

    // Resume idle chat
    this.proactive.startIdleChat(deviceId).catch(() => {});
    this.sessions.resetIdleTimer(deviceId, () => {
      this.endConversation(deviceId);
    });
  }

  private async runPipeline(
    deviceId: string,
    transcript: string,
    memories: { fact: string; category: string }[],
    history: { role: string; content: string }[],
    voiceOptions?: { voice?: string; speed?: number; stability?: number },
    context?: {
      timezone?: string;
      weatherEnabled?: boolean;
      latitude?: number;
      longitude?: number;
    },
    moodHistory?: { date: string; mood: string; note?: string }[],
    ttsEnabled = true,
    sfxEnabled = true,
    gen?: number,
  ) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    // Refresh weather if enabled (cached, 15min TTL)
    if (context?.weatherEnabled && context.latitude && context.longitude) {
      await this.aiService.refreshWeather(context.latitude, context.longitude);
    }

    // AbortController lets us cancel the in-flight ElevenLabs fetch and stop
    // Gemini token generation when this pipeline is superseded by a new one.
    const abortController = new AbortController();

    const pipeline = this.aiService.processTranscript(
      transcript,
      memories,
      history,
      voiceOptions,
      context,
      moodHistory,
      ttsEnabled,
      abortController.signal,
    );

    let started = false;
    let fullResponseText = '';
    let cacheKeys: { hash: string; sentence: string }[] = [];
    let lastEmotion: string | null = null;

    // Emotion tag → ESP32 face expression mapping
    const emotionToExpression: Record<string, string> = {
      happy: 'happy',
      excited: 'encouraging',
      calm: 'calm',
      sad: 'sad',
      confused: 'confused',
      focused: 'focused',
      sarcastic: 'encouraging',
      sympathetic: 'calm',
      neutral: 'speaking',
    };

    for await (const event of pipeline) {
      // Stop if interrupted by user tap OR superseded by a newer pipeline.
      // Abort the signal first so the generator's current await gets cancelled.
      if (this.sessions.isInterrupted(deviceId)) {
        abortController.abort();
        break;
      }
      if (gen !== undefined && !this.isPipelineCurrent(deviceId, gen)) {
        this.logger.log(
          `[${deviceId}] Pipeline gen ${gen} superseded — aborting`,
        );
        abortController.abort();
        break;
      }

      if (event.type === 'text') {
        this.sendToDevice(deviceId, 'response:text', {
          text: event.text,
          isFinal: false,
        });

        // Send face expression when emotion changes between sentences.
        // withSound:false — TTS audio follows immediately, no emotion clip needed.
        if (event.emotion && event.emotion !== lastEmotion) {
          const expr = emotionToExpression[event.emotion] ?? 'speaking';
          this.sendToDevice(deviceId, 'face:expression', {
            expression: expr,
            withSound: false,
          });
          lastEmotion = event.emotion;
        }

        // Send SFX event before TTS frames so the clip plays first.
        if (event.sfx && sfxEnabled) {
          this.sendToDevice(deviceId, 'audio:sfx', { clip: event.sfx });
        }
      } else if (event.type === 'audio') {
        if (!started) {
          // Final guard: re-check supersession immediately before committing
          // response:start to the device. Two pipelines could both pass the
          // per-iteration check above (both saw their gen as current) but only
          // one should win the right to send audio.
          if (gen !== undefined && !this.isPipelineCurrent(deviceId, gen)) {
            this.logger.log(
              `[${deviceId}] Pipeline gen ${gen} superseded at response:start — aborting`,
            );
            abortController.abort();
            break;
          }
          this.sendToDevice(deviceId, 'response:start', { type: 'audio' });
          session.state = 'speaking';
          this.sendToDevice(deviceId, 'state:update', { state: 'speaking' });
          started = true;
        }
        await this.sendFramedOpusToDevice(deviceId, event.data);
      } else if (event.type === 'done') {
        fullResponseText = event.fullText;
        cacheKeys = event.cacheKeys;
      }
    }

    // Only finalize if not superseded by a newer pipeline
    if (gen === undefined || this.isPipelineCurrent(deviceId, gen)) {
      this.sendToDevice(deviceId, 'response:end', {
        fullText: fullResponseText,
        cacheKeys,
      });

      // Save assistant response
      if (session.conversationId && fullResponseText) {
        await this.persistence.saveMessage(
          session.conversationId,
          'assistant',
          fullResponseText,
        );
      }
    }
  }

  // ── Conversation lifecycle ────────────────────────────────────

  /**
   * Lazily creates a conversation the first time a real message is about to be
   * saved for this session. Subsequent calls within the same session are no-ops.
   * Returns the conversation ID.
   *
   * This is intentionally deferred from onAudioStart so that aborted sessions
   * (STT failure, empty transcript, connection drop before speech) leave no
   * orphaned conversation rows in the database.
   */
  private async ensureConversation(deviceId: string): Promise<string> {
    const session = this.sessions.get(deviceId);
    if (!session) throw new Error(`No session for device ${deviceId}`);

    if (!session.conversationId) {
      // Tag the conversation row with the device's current guest_mode state at
      // creation time. This is frozen for the conversation's lifetime — mid-
      // session flips of the setting don't retroactively reclassify the row.
      const device = await this.persistence.getDevice(deviceId).catch(() => null);
      const guestMode = device?.settingsJson?.guest_mode === true;
      const conversation = await this.persistence.createConversation(
        deviceId,
        guestMode,
      );
      session.conversationId = conversation.id;
      this.logger.log(`[${deviceId}] Conversation created: ${conversation.id}`);
      this.sendToDevice(deviceId, 'session:start', {
        sessionId: conversation.id,
      });
    }

    return session.conversationId;
  }

  private async endConversation(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session?.conversationId) return;

    const conversationId = session.conversationId;
    session.conversationId = null;

    await this.persistence.endConversation(conversationId);
    this.sendToDevice(deviceId, 'session:end', {
      sessionId: conversationId,
      reason: 'timeout',
    });

    // Guest mode: don't extract memories from a session where the speaker
    // may not even be the device owner — avoids contaminating the owner's
    // memory pool with a visitor's facts.
    const device = await this.persistence.getDevice(deviceId).catch(() => null);
    if (device?.settingsJson?.guest_mode === true) {
      this.logger.log(
        `[${deviceId}] Guest mode — skipping memory extraction for ${conversationId}`,
      );
      return;
    }

    // Extract memories in background (don't block the session end)
    this.memoriesService
      .extractFromConversation(conversationId, deviceId)
      .catch((err) =>
        this.logger.warn(`Memory extraction failed: ${err.message}`),
      );
  }

  // ── Server-side heartbeat ─────────────────────────────────

  private lastDbRefresh = new Map<string, number>();
  private static readonly DB_REFRESH_INTERVAL_MS = 120_000; // update lastSeenAt every 2 min

  private heartbeat() {
    const now = Date.now();

    for (const [deviceId, socket] of this.deviceToSocket.entries()) {
      const lastSeen = this.lastPong.get(deviceId) ?? 0;

      if (now - lastSeen > AudioGateway.HEARTBEAT_TIMEOUT_MS) {
        this.logger.warn(
          `Device ${deviceId} missed heartbeat — closing dead connection`,
        );
        socket.terminate(); // Hard close — triggers handleDisconnect
        this.lastDbRefresh.delete(deviceId);
        continue;
      }

      // Send ping (ws library handles pong automatically on client side)
      if (socket.readyState === 1) {
        socket.ping();
      }

      // Periodically update lastSeenAt in DB so the REST API reflects online status
      const lastRefresh = this.lastDbRefresh.get(deviceId) ?? 0;
      if (now - lastRefresh > AudioGateway.DB_REFRESH_INTERVAL_MS) {
        this.lastDbRefresh.set(deviceId, now);
        this.persistence.updateLastSeen(deviceId).catch(() => {});
      }
    }
  }

  // ── Transport helpers ─────────────────────────────────────────

  /** Send a pre-encoded framed-Opus buffer to a device as a full response,
   *  wrapped in response:start / response:end.
   *  Returns true if the device was reachable. */
  async sendVoiceMessage(
    deviceId: string,
    framedOpus: Buffer,
  ): Promise<boolean> {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return false;
    this.sendToDevice(deviceId, 'response:start', { type: 'intercom' });
    await this.sendFramedOpusToDevice(deviceId, framedOpus);
    this.sendToDevice(deviceId, 'response:end', {
      fullText: '',
      cacheKeys: [],
    });
    return true;
  }

  /** Accept a PCM audio buffer from the mobile app, transcribe it via STT,
   *  and run the full AI pipeline (STT → LLM → TTS) targeting the device speaker.
   *  Returns the transcript immediately; the pipeline fires asynchronously.
   *  Returns { transcript: '', dispatched: false } if speech was not recognised
   *  or the device has no active session. */
  async handleAppVoiceInput(
    deviceId: string,
    pcm: Buffer,
  ): Promise<{ transcript: string; dispatched: boolean }> {
    const sttResult = await this.aiService.transcribeOnce(pcm, {
      sampleRate: 16000,
    });

    if (!sttResult.transcript.trim()) {
      return { transcript: '', dispatched: false };
    }

    const session = this.sessions.get(deviceId);
    if (!session) {
      // Device is offline — pipeline has nowhere to deliver audio
      return { transcript: sttResult.transcript, dispatched: false };
    }

    // Fire the same pipeline the device tap would trigger, non-blocking.
    // onSttFinal handles conversation persistence, LLM, TTS, and WS delivery.
    void this.onSttFinal(deviceId, sttResult);

    return { transcript: sttResult.transcript, dispatched: true };
  }

  /** Handle a voice recording from the mobile app and return the AI response
   *  directly to the app (text + MP3 audio) instead of sending it to the device.
   *  The full pipeline (STT → LLM → TTS) runs synchronously and the result is
   *  returned in the HTTP response. Does NOT require the device to be online. */
  async handleAppVoiceInputForApp(
    deviceId: string,
    pcm: Buffer,
    existingConversationId?: string,
  ): Promise<{
    transcript: string;
    response: string;
    audio: string;
    mimeType: string;
    conversationId: string;
  }> {
    const empty = {
      transcript: '',
      response: '',
      audio: '',
      mimeType: '',
      conversationId: existingConversationId ?? '',
    };

    // 1. STT
    const sttResult = await this.aiService.transcribeOnce(pcm, {
      sampleRate: 16000,
    });
    if (!sttResult.transcript.trim()) return empty;

    this.logger.log(
      `[${deviceId}] App-reply transcript: "${sttResult.transcript}"`,
    );

    // 2. Fetch device settings and context (from DB — device doesn't need to be online)
    const device = await this.persistence.getDevice(deviceId);
    const settings = device?.settingsJson ?? {};

    const voiceOptions = {
      voice: settings.voice_preset as string | undefined,
      speed: settings.voice_speed as number | undefined,
      stability: settings.voice_stability as number | undefined,
      language: (settings.language as 'en' | 'id' | undefined) ?? 'en',
    };
    const guestMode = settings.guest_mode === true;
    const identityCtx2 = this.buildIdentityContext(deviceId);
    const context = {
      timezone: settings.timezone as string | undefined,
      weatherEnabled: settings.integrations_weather as boolean | undefined,
      latitude: settings.latitude as number | undefined,
      longitude: settings.longitude as number | undefined,
      language: (settings.language as 'en' | 'id' | undefined) ?? 'en',
      guestMode,
      identityContext: identityCtx2 || undefined,
    };

    // 3. Fetch memories, history, mood in parallel
    // Use the ongoing app conversation for history context, falling back to
    // the device's active session conversation if one exists.
    const session = this.sessions.get(deviceId);
    const historyConvId =
      existingConversationId || session?.conversationId;

    const [memories, moodHistory, history] = await Promise.all([
      guestMode
        ? Promise.resolve([])
        : this.memoriesService.getStratifiedSample(deviceId, 10),
      guestMode
        ? Promise.resolve([])
        : this.moodJournal.getRecentMoods(deviceId).catch(() => []),
      historyConvId
        ? this.persistence.getRecentHistory(historyConvId)
        : Promise.resolve([]),
    ]);

    // Bump access on used memories
    if (memories.length > 0) {
      this.memoriesService
        .bumpAccessed(memories.map((m) => m.id))
        .catch(() => {});
    }

    const moodEntries = moodHistory.map((m) => ({
      date: m.date,
      mood: m.mood,
      note: m.note ?? undefined,
    }));

    // 4. Refresh weather if enabled
    if (context.weatherEnabled && context.latitude && context.longitude) {
      await this.aiService.refreshWeather(context.latitude, context.longitude);
    }

    // 5. Reuse existing conversation or create a new one
    let conversationId: string;
    if (existingConversationId) {
      conversationId = existingConversationId;
    } else {
      const conversation = await this.persistence.createConversation(
        deviceId,
        guestMode,
      );
      conversationId = conversation.id;
      // Extract memories from any stale conversations that were just closed —
      // but only when guest mode is off. The defense-in-depth guard inside
      // MemoriesService.extractFromConversation will also bail on guest-tagged
      // conversations, so this is belt-and-braces.
      if (!guestMode) {
        const closedIds = (conversation as any).closedConversationIds as
          | string[]
          | undefined;
        if (closedIds?.length) {
          for (const closedId of closedIds) {
            this.memoriesService
              .extractFromConversation(closedId, deviceId)
              .catch((err) =>
                this.logger.warn(`Memory extraction failed: ${err.message}`),
              );
          }
        }
      }
    }
    await this.persistence.saveMessage(
      conversationId,
      'user',
      sttResult.transcript,
    );

    // 6. Run LLM (text only, no TTS — we'll synthesize MP3 separately)
    //    Collect cleaned text from 'text' events (emotion/sfx tags stripped)
    //    rather than 'done.fullText' which is the raw LLM output with tags.
    const cleanSentences: string[] = [];
    const pipeline = this.aiService.processTranscript(
      sttResult.transcript,
      memories,
      history,
      voiceOptions,
      context,
      moodEntries,
      false, // ttsEnabled = false
    );
    for await (const event of pipeline) {
      if (event.type === 'text') {
        cleanSentences.push(event.text);
      }
    }
    const fullText = cleanSentences.join(' ');

    if (!fullText) {
      return {
        transcript: sttResult.transcript,
        response: '',
        audio: '',
        mimeType: '',
        conversationId,
      };
    }

    // 7. Synthesize TTS as MP3 for app playback
    let audioBase64 = '';
    let mimeType = '';
    try {
      const mp3Buffer = await this.aiService.synthesizeForApp(
        fullText,
        voiceOptions,
      );
      audioBase64 = mp3Buffer.toString('base64');
      mimeType = 'audio/mpeg';
    } catch (err: any) {
      this.logger.warn(
        `[${deviceId}] App TTS synthesis failed: ${err.message}`,
      );
      // Graceful degradation: return text without audio
    }

    // 8. Save assistant message
    await this.persistence.saveMessage(conversationId, 'assistant', fullText);

    return {
      transcript: sttResult.transcript,
      response: fullText,
      audio: audioBase64,
      mimeType,
      conversationId,
    };
  }

  /** Send a single raw Opus frame to a device without framing headers.
   *  Used by IntercomGateway for real-time streaming — caller manages
   *  response:start / response:end lifecycle events. */
  sendOpusFrameToDevice(deviceId: string, opusFrame: Buffer): void {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return;
    socket.send(opusFrame);
  }

  // ── Walkie-talkie: device → app ───────────────────────────────────────────

  /** Device started a walkie-talkie reply. Begin accumulating Opus frames. */
  private onIntercomReplyStart(deviceId: string): void {
    const session = this.sessions.get(deviceId);
    if (!session) return;
    session.intercomReply = true;
    session.intercomFrames = [];
    this.intercomSessions.sendJsonToApp(
      deviceId,
      'intercom:device:talking',
      {},
    );
    this.logger.log(`[${deviceId}] Walkie-talkie reply started`);
  }

  /** Device finished its reply. Decode accumulated Opus → PCM → WAV → push to app. */
  private async onIntercomReplyEnd(deviceId: string): Promise<void> {
    const session = this.sessions.get(deviceId);
    if (!session?.intercomReply) return;

    session.intercomReply = false;
    const frames = session.intercomFrames;
    session.intercomFrames = [];

    if (frames.length === 0) {
      this.intercomSessions.sendJsonToApp(deviceId, 'intercom:device:done', {});
      return;
    }

    // Decode each raw Opus frame → 640 bytes of 16kHz/mono/16-bit PCM
    const pcmChunks: Buffer[] = [];
    for (const frame of frames) {
      try {
        pcmChunks.push(this.codec.decode(frame));
      } catch {
        // Skip corrupt frames — a few missing frames are tolerable
      }
    }

    const pcm = Buffer.concat(pcmChunks);
    const wav = this.buildWav(pcm);

    this.intercomSessions.sendBinaryToApp(deviceId, wav);
    this.intercomSessions.sendJsonToApp(deviceId, 'intercom:device:done', {});
    this.logger.log(
      `[${deviceId}] Walkie-talkie reply forwarded to app (${frames.length} frames, ${pcm.length} PCM bytes)`,
    );
  }

  /** Wrap raw 16kHz/mono/16-bit PCM in a standard 44-byte WAV header. */
  private buildWav(pcm: Buffer, sampleRate = 16000): Buffer {
    const channels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * channels * (bitsPerSample / 8);
    const blockAlign = channels * (bitsPerSample / 8);
    const header = Buffer.alloc(44);
    header.write('RIFF', 0);
    header.writeUInt32LE(36 + pcm.length, 4);
    header.write('WAVE', 8);
    header.write('fmt ', 12);
    header.writeUInt32LE(16, 16); // PCM chunk size
    header.writeUInt16LE(1, 20); // PCM format
    header.writeUInt16LE(channels, 22);
    header.writeUInt32LE(sampleRate, 24);
    header.writeUInt32LE(byteRate, 28);
    header.writeUInt16LE(blockAlign, 32);
    header.writeUInt16LE(bitsPerSample, 34);
    header.write('data', 36);
    header.writeUInt32LE(pcm.length, 40);
    return Buffer.concat([header, pcm]);
  }

  sendToDevice(deviceId: string, event: string, data: any) {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return;
    socket.send(JSON.stringify({ event, data }));
  }

  /** Called by DevicesController after settings are saved so the in-memory session stays in sync. */
  onSettingsUpdated(deviceId: string, dto: { language?: 'en' | 'id' }) {
    if (dto.language) this.sessions.setLanguage(deviceId, dto.language);
  }

  private sendBinaryToDevice(deviceId: string, data: Buffer) {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return;
    socket.send(data);
  }

  /**
   * Send length-prefixed Opus frames as individual WebSocket binary messages.
   * Backend Opus codec produces: [2-byte BE length][opus frame][2-byte BE length][opus frame]...
   * ESP32 firmware expects one raw Opus frame per WS binary message.
   * Paced at ~15ms per frame to avoid overwhelming the ESP32's WS/TLS buffer.
   */
  private async sendFramedOpusToDevice(
    deviceId: string,
    framedOpus: Buffer,
  ): Promise<number> {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return 0;

    let offset = 0;
    let frameCount = 0;

    while (offset + 2 <= framedOpus.length) {
      const frameLen = framedOpus.readUInt16BE(offset);
      offset += 2;

      if (offset + frameLen > framedOpus.length) {
        this.logger.warn(
          `Framed opus truncated at offset ${offset}, expected ${frameLen} bytes`,
        );
        break;
      }

      // Re-check connection periodically (every 20 frames)
      if (frameCount > 0 && frameCount % 20 === 0) {
        if (!socket || socket.readyState !== 1) break;
      }

      const frame = framedOpus.subarray(offset, offset + frameLen);
      socket.send(frame);
      offset += frameLen;
      frameCount++;

      // Pace at ~15ms per frame (Opus frame = 20ms audio).
      // Prevents overwhelming ESP32's TLS decrypt + WS buffer.
      if (frameCount % 5 === 0) {
        await new Promise((r) => setTimeout(r, 75));
      }
    }

    return frameCount;
  }

  private sendJson(client: WebSocket, event: string, data: any) {
    if (client.readyState !== 1) return;
    client.send(JSON.stringify({ event, data }));
  }

  private reject(client: WebSocket, reason: string) {
    this.sendJson(client, 'error', { code: 'AUTH_FAILED', message: reason });
    client.close(4001, reason);
  }

  private extractDeviceToken(req: IncomingMessage): string | null {
    // 1. Authorization header (ESP32 / Node clients)
    const auth = req.headers['authorization'];
    if (auth) {
      const match = auth.match(/^DeviceToken\s+(.+)$/i);
      if (match?.[1]) return match[1];
    }
    // 2. Query parameter (browser WebSocket — cannot set custom headers)
    const url = new URL(req.url ?? '', `http://${req.headers.host}`);
    return url.searchParams.get('token');
  }

  /** Build a face recognition identity string for LLM context injection. */
  private buildIdentityContext(deviceId: string): string {
    const session = this.sessions.get(deviceId);
    const identity = session?.currentIdentity;
    if (!identity) return '';
    if (identity.unknown) return 'An unknown person is currently present at the desk.';
    return `${identity.name} is currently present at the desk.`;
  }

  sendVisionCapture(cameraDeviceId: string): void {
    this.sendToDevice(cameraDeviceId, 'vision:capture', {});
  }

  setPendingEnrollment(cameraDeviceId: string, userId: string, name: string): void {
    this.visionHandler.setPendingEnrollment(cameraDeviceId, userId, name);
  }
}
