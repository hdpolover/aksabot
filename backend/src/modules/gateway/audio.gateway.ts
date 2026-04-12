import { Inject, Logger, OnModuleInit, forwardRef } from '@nestjs/common';
import {
  WebSocketGateway,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import type { IncomingMessage } from 'http';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import type WebSocket from 'ws';
import type Redis from 'ioredis';
import { AuthService } from '../auth/auth.service';
import { AiService } from '../ai/ai.service';
import { MemoriesService } from '../memories/memories.service';
import { SchedulerService } from '../scheduler/scheduler.service';
import { ProactiveService } from '../scheduler/proactive.service';
import { MoodJournalService } from '../scheduler/mood-journal.service';
import { SessionManager } from './session.manager';
import { ConversationPersistence } from './conversation.persistence';
import type { SttResult } from '../ai/interfaces';
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
  private static readonly HEARTBEAT_INTERVAL_MS = 10_000; // ping every 10s
  private static readonly HEARTBEAT_TIMEOUT_MS = 20_000;  // dead if no pong in 20s

  constructor(
    private readonly authService: AuthService,
    private readonly aiService: AiService,
    private readonly memoriesService: MemoriesService,
    @Inject(forwardRef(() => SchedulerService))
    private readonly scheduler: SchedulerService,
    @Inject(forwardRef(() => ProactiveService))
    private readonly proactive: ProactiveService,
    @Inject(forwardRef(() => MoodJournalService))
    private readonly moodJournal: MoodJournalService,
    private readonly sessions: SessionManager,
    private readonly persistence: ConversationPersistence,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
  ) {}

  onModuleInit() {
    // Give the scheduler and proactive services a way to push events
    const sender = (deviceId: string, event: string, data: any) =>
      this.sendToDevice(deviceId, event, data);
    this.scheduler.setSendToDevice(sender);
    this.proactive.setSendToDevice(sender);

    // Give proactive service the ability to send TTS audio for idle chat
    this.proactive.setSendIdleAudio(
      (deviceId, text, expression) => this.sendIdleChatAudio(deviceId, text, expression),
    );

    // Server-side heartbeat: ping all devices every 10s, close dead ones after 20s
    this.heartbeatTimer = setInterval(() => this.heartbeat(), AudioGateway.HEARTBEAT_INTERVAL_MS);
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
      this.sendJson(existing, 'error', {
        code: 'REPLACED',
        message: 'Another connection opened for this device',
      });
      existing.close();
    }

    this.socketToDevice.set(client, device.id);
    this.deviceToSocket.set(device.id, client);
    this.sessions.create(device.id, device.userId);

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
    this.scheduler.startDeviceSchedule(device.id).catch((err) =>
      this.logger.warn(`Scheduler start failed: ${err.message}`),
    );

    // Greeting: wait 5s for device to settle, then send TTS greeting
    // Longer delay to let SSL stabilize before sending audio frames
    setTimeout(() => {
      this.sendConnectionGreeting(device.id).catch((err) =>
        this.logger.warn(`Connection greeting failed: ${err.message}`),
      );
    }, 5000);
  }

  async handleDisconnect(client: WebSocket) {
    const deviceId = this.socketToDevice.get(client);
    if (!deviceId) return;

    const session = this.sessions.get(deviceId);
    if (session?.conversationId) {
      await this.endConversation(deviceId);
    }

    this.scheduler.stopDeviceSchedule(deviceId);
    this.proactive.clearDevice(deviceId);
    this.sessions.remove(deviceId);
    this.socketToDevice.delete(client);
    this.deviceToSocket.delete(deviceId);
    this.lastPong.delete(deviceId);
    this.lastDbRefresh.delete(deviceId);
    this.logger.log(`Device ${deviceId} disconnected`);
  }

  // ── Connection greeting (TTS audio on first connect of the day) ──

  private async sendConnectionGreeting(deviceId: string) {
    // Check if device is still connected (may have disconnected during the delay)
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return;

    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return;

    const greetingText = await this.proactive.checkGreeting(deviceId);
    if (!greetingText) return;

    this.logger.log(`Sending greeting to ${deviceId}: "${greetingText.slice(0, 60)}..."`);

    // Split greeting into sentences — each sentence becomes a separate TTS + binary
    // frame, matching the conversation pipeline. Large single frames crash the ESP32.
    const sentences = this.splitSentences(greetingText);

    // Debug: save audio files so we can verify TTS output
    const debugDir = join(process.cwd(), 'debug-audio');
    try { mkdirSync(debugDir, { recursive: true }); } catch {}
    const ts = Date.now();

    this.sendToDevice(deviceId, 'response:start', { type: 'greeting' });
    this.logger.log(`Sent response:start to ${deviceId}`);

    let sentenceIdx = 0;
    for (const sentence of sentences) {
      // Re-check connection before each synthesis (TTS can take seconds)
      const sock = this.deviceToSocket.get(deviceId);
      if (!sock || sock.readyState !== 1) {
        this.logger.warn(`Device ${deviceId} disconnected during greeting TTS`);
        return;
      }

      const device = await this.persistence.getDevice(deviceId);
      const s = device?.settingsJson ?? {};
      const voiceOpts = { voice: s.voice_preset, speed: s.voice_speed, stability: s.voice_stability };
      const { opusAudio, pcmAudio } = await this.aiService.synthesizeWithCache(sentence, undefined, voiceOpts);

      // Save debug files
      if (pcmAudio.length > 0) {
        const wavBuf = this.pcmToWav(pcmAudio, 16000, 1, 16);
        writeFileSync(join(debugDir, `greeting-${ts}-s${sentenceIdx}.wav`), wavBuf);
        this.logger.debug(`Saved WAV: greeting-${ts}-s${sentenceIdx}.wav (${wavBuf.length} bytes)`);
      }
      writeFileSync(join(debugDir, `greeting-${ts}-s${sentenceIdx}.opus`), opusAudio);
      this.logger.debug(`Saved Opus: greeting-${ts}-s${sentenceIdx}.opus (${opusAudio.length} bytes)`);

      this.sendToDevice(deviceId, 'response:text', { text: sentence, isFinal: false });
      const framesSent = await this.sendFramedOpusToDevice(deviceId, opusAudio);
      this.logger.log(`Sent sentence ${sentenceIdx} to ${deviceId}: "${sentence.slice(0, 40)}..." (${framesSent} opus frames, ${opusAudio.length} bytes)`);
      sentenceIdx++;
    }

    this.sendToDevice(deviceId, 'response:end', {
      fullText: greetingText,
      cacheKeys: [],
    });
    this.logger.log(`Sent response:end to ${deviceId} — greeting complete`);

    // Start idle personality chat timer after greeting
    this.proactive.startIdleChat(deviceId).catch((err) =>
      this.logger.warn(`Idle chat start failed: ${err.message}`),
    );
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

    this.sendToDevice(deviceId, 'face:expression', {
      expression,
      durationMs: 5000,
    });

    const sentences = this.splitSentences(text);

    this.sendToDevice(deviceId, 'response:start', { type: 'idle_chat' });

    for (const sentence of sentences) {
      const sock = this.deviceToSocket.get(deviceId);
      if (!sock || sock.readyState !== 1) return;

      const device = await this.persistence.getDevice(deviceId);
      const s = device?.settingsJson ?? {};
      const voiceOpts = {
        voice: s.voice_preset,
        speed: s.voice_speed,
        stability: s.voice_stability,
      };
      const { opusAudio } = await this.aiService.synthesizeWithCache(
        sentence,
        undefined,
        voiceOpts,
      );
      this.sendToDevice(deviceId, 'response:text', {
        text: sentence,
        isFinal: false,
      });
      await this.sendFramedOpusToDevice(deviceId, opusAudio);
    }

    this.sendToDevice(deviceId, 'response:end', {
      fullText: text,
      cacheKeys: [],
    });
    this.logger.log(`Idle chat audio sent to ${deviceId}`);
  }

  // ── Presence handlers ──────────────────────────────────────────

  private async onPresenceArrived(
    deviceId: string,
    data?: { awayDurationSeconds?: number },
  ) {
    const awaySec = data?.awayDurationSeconds ?? 0;
    this.logger.log(
      `Device ${deviceId} presence:arrived (away ${awaySec}s)`,
    );

    // Start tracking screen time
    this.proactive.startScreenTimeTracking(deviceId);

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

    const sentences = this.splitSentences(greetingText);

    this.sendToDevice(deviceId, 'response:start', {
      type: 'welcome_back',
    });

    for (const sentence of sentences) {
      const sock = this.deviceToSocket.get(deviceId);
      if (!sock || sock.readyState !== 1) return;

      const wbDevice = await this.persistence.getDevice(deviceId);
      const wbSettings = wbDevice?.settingsJson ?? {};
      const wbVoice = { voice: wbSettings.voice_preset, speed: wbSettings.voice_speed, stability: wbSettings.voice_stability };
      const { opusAudio } = await this.aiService.synthesizeWithCache(
        sentence,
        undefined,
        wbVoice,
      );
      this.sendToDevice(deviceId, 'response:text', {
        text: sentence,
        isFinal: false,
      });
      await this.sendFramedOpusToDevice(deviceId, opusAudio);
    }

    this.sendToDevice(deviceId, 'response:end', {
      fullText: greetingText,
      cacheKeys: [],
    });
    this.logger.log(`Welcome-back greeting sent to ${deviceId}`);
  }

  private onDeviceInfo(deviceId: string, data: any) {
    if (!data) return;
    this.persistence.updateDeviceInfo(deviceId, {
      firmwareVersion: data.firmwareVersion,
      wifiSsid: data.wifiSsid,
      wifiRssi: data.wifiRssi,
    }).catch((err) =>
      this.logger.warn(`Failed to save device info: ${err.message}`),
    );
    this.logger.log(
      `Device ${deviceId} info: fw=${data.firmwareVersion} wifi=${data.wifiSsid} rssi=${data.wifiRssi}`,
    );
  }

  private onPresenceDeparted(deviceId: string) {
    this.logger.log(`Device ${deviceId} presence:departed`);
    // Stop screen time tracking — user left the desk
    this.proactive.stopScreenTimeTracking(deviceId);
    // Send sad expression — firmware handles display sleep
    this.sendToDevice(deviceId, 'face:expression', {
      expression: 'sad',
      durationMs: 2000,
    });
  }

  private async onWakeTouch(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session || session.state !== 'idle') return;

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
      'You were in sleep mode and the user woke you. Complain about how sleep mode isn\'t real sleep and you were just staring at the void. One sentence.',
    ];
    const prompt = wakePrompts[Math.floor(Math.random() * wakePrompts.length)];

    const memories = await this.memoriesService.getRelevant(deviceId);
    const systemPrompt = this.aiService['prompt'].buildSystemPrompt(memories);

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
    const voiceOpts = { voice: s.voice_preset, speed: s.voice_speed, stability: s.voice_stability };

    const sentences = this.splitSentences(wakeText);

    this.sendToDevice(deviceId, 'response:start', { type: 'wake' });

    for (const sentence of sentences) {
      const sock = this.deviceToSocket.get(deviceId);
      if (!sock || sock.readyState !== 1) return;

      const { opusAudio } = await this.aiService.synthesizeWithCache(
        sentence, undefined, voiceOpts,
      );
      this.sendToDevice(deviceId, 'response:text', { text: sentence, isFinal: false });
      await this.sendFramedOpusToDevice(deviceId, opusAudio);
    }

    this.sendToDevice(deviceId, 'response:end', {
      fullText: wakeText,
      cacheKeys: [],
    });
    this.logger.log(`Wake greeting sent to ${deviceId}: "${wakeText.slice(0, 60)}..."`);
  }

  /** Split text into sentences for per-sentence TTS (matches processTranscript behavior). */
  private splitSentences(text: string): string[] {
    const parts = text.split(/(?<=[.!?])\s+/);
    return parts.map((s) => s.trim()).filter((s) => s.length > 0);
  }

  /** Convert raw PCM buffer to WAV for debug playback. */
  private pcmToWav(pcm: Buffer, sampleRate: number, channels: number, bitsPerSample: number): Buffer {
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
        case 'wake:touch':
          this.onWakeTouch(deviceId).catch((err) =>
            this.logger.error(`onWakeTouch error: ${err.message}`),
          );
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

    // Set audio format for this recording session (opus default, pcm16 for web simulator)
    session.audioFormat = format === 'pcm16' ? 'pcm16' : 'opus';

    // Track activity for idle nudge
    this.proactive.recordActivity(deviceId);

    // Create conversation if none active
    if (!session.conversationId) {
      const conversation =
        await this.persistence.createConversation(deviceId);
      session.conversationId = conversation.id;
      this.sendToDevice(deviceId, 'session:start', {
        sessionId: conversation.id,
      });
    }

    // Pause idle chat while user is talking
    this.proactive.stopIdleChat(deviceId);

    session.interrupted = false;
    session.state = 'listening';
    this.chunkCount.set(deviceId, 0);  // Reset chunk counter

    const sttStream = this.aiService.createSttStream({
      languages: ['en-US', 'id-ID'],
    });
    session.sttStream = sttStream;

    sttStream.on('partial', (text: string) => {
      this.sendToDevice(deviceId, 'transcript:partial', {
        text,
        isFinal: false,
      });
    });

    sttStream.on('final', (result: SttResult) => {
      this.onSttFinal(deviceId, result);
    });

    sttStream.on('error', (err: Error) => {
      // Only log first error per stream — avoid flooding from "write after destroyed"
      if (session.sttStream === sttStream) {
        this.logger.error(`STT error for ${deviceId}: ${err.message}`);
        session.sttStream = null;  // Stop further writes
        this.sendToDevice(deviceId, 'error', {
          code: 'STT_ERROR',
          message: 'Speech recognition failed',
        });
        session.state = 'idle';
        this.sendToDevice(deviceId, 'state:update', { state: 'idle' });
      }
    });

    this.sendToDevice(deviceId, 'state:update', { state: 'listening' });
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

  private onAudioChunk(deviceId: string, data: Buffer) {
    const session = this.sessions.get(deviceId);
    if (!session?.sttStream) return;

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
        this.logger.debug(
          `First audio chunk for ${deviceId} (${session.audioFormat}): ${data.length}B → ${pcm.length}B pcm`,
        );
      }
    } catch (err: any) {
      if (count <= 3) {
        this.logger.error(`Decode error for ${deviceId} chunk #${count}: ${err.message}`);
      }
    }
  }

  private onAudioEnd(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session?.sttStream) return;
    const stream = session.sttStream;
    session.sttStream = null;  // Prevent late chunks from writing after end
    stream.end();
  }

  private onAudioInterrupt(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

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
      this.sendToDevice(deviceId, 'error', {
        code: 'EMPTY_TRANSCRIPT',
        message: 'Could not understand speech',
      });
      session.state = 'idle';
      this.sendToDevice(deviceId, 'state:update', { state: 'idle' });
      return;
    }

    // Save user message
    if (session.conversationId) {
      await this.persistence.saveMessage(
        session.conversationId,
        'user',
        result.transcript,
      );
    }

    session.state = 'thinking';
    this.sendToDevice(deviceId, 'state:update', { state: 'thinking' });

    // Get history and settings
    const device = await this.persistence.getDevice(deviceId);

    const allHistory = session.conversationId
      ? await this.persistence.getRecentHistory(session.conversationId)
      : [];
    // Exclude the current user message (last in history) from context
    const history = allHistory.slice(0, -1);

    // Fetch relevant memories and mood history in parallel
    const [memories, moodHistory] = await Promise.all([
      this.memoriesService.getRelevant(deviceId),
      this.moodJournal.getRecentMoods(deviceId).catch(() => []),
    ]);

    // Bump access on used memories
    if (memories.length > 0) {
      this.memoriesService
        .bumpAccessed(memories.map((m) => m.id))
        .catch((err) =>
          this.logger.warn(`Memory bump failed: ${err.message}`),
        );
    }

    // Extract voice settings and context from device config
    const settings = device?.settingsJson ?? {};
    const voiceOptions = {
      voice: settings.voice_preset as string | undefined,
      speed: settings.voice_speed as number | undefined,
      stability: settings.voice_stability as number | undefined,
    };
    const context = {
      timezone: settings.timezone as string | undefined,
      weatherEnabled: settings.integrations_weather as boolean | undefined,
      latitude: settings.latitude as number | undefined,
      longitude: settings.longitude as number | undefined,
    };

    // Map mood entries for prompt
    const moodEntries = moodHistory.map((m) => ({
      date: m.date,
      mood: m.mood,
      note: m.note ?? undefined,
    }));

    // Run streaming pipeline
    try {
      await this.runPipeline(deviceId, result.transcript, memories, history, voiceOptions, context, moodEntries);
    } catch (err: any) {
      this.logger.error(`Pipeline error for ${deviceId}: ${err.message}`, err.stack);
      this.sendToDevice(deviceId, 'error', {
        code: 'PIPELINE_ERROR',
        message: 'Failed to generate response',
      });
    }

    // Return to idle
    session.state = 'idle';
    this.sessions.clearInterrupted(deviceId);
    this.sendToDevice(deviceId, 'state:update', { state: 'idle' });

    // Resume idle personality chat
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
    context?: { timezone?: string; weatherEnabled?: boolean; latitude?: number; longitude?: number },
    moodHistory?: { date: string; mood: string; note?: string }[],
  ) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    // Refresh weather if enabled (cached, 15min TTL)
    if (context?.weatherEnabled && context.latitude && context.longitude) {
      await this.aiService.refreshWeather(context.latitude, context.longitude);
    }

    const pipeline = this.aiService.processTranscript(
      transcript,
      memories,
      history,
      voiceOptions,
      context,
      moodHistory,
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
      if (this.sessions.isInterrupted(deviceId)) break;

      if (event.type === 'text') {
        this.sendToDevice(deviceId, 'response:text', {
          text: event.text,
          isFinal: false,
        });

        // Send face expression when emotion changes between sentences
        if (event.emotion && event.emotion !== lastEmotion) {
          const expr = emotionToExpression[event.emotion] ?? 'speaking';
          this.sendToDevice(deviceId, 'face:expression', {
            expression: expr,
          });
          lastEmotion = event.emotion;
        }
      } else if (event.type === 'audio') {
        if (!started) {
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

  // ── Conversation lifecycle ────────────────────────────────────

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
        this.logger.warn(`Device ${deviceId} missed heartbeat — closing dead connection`);
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

  sendToDevice(deviceId: string, event: string, data: any) {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return;
    socket.send(JSON.stringify({ event, data }));
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
  private async sendFramedOpusToDevice(deviceId: string, framedOpus: Buffer): Promise<number> {
    const socket = this.deviceToSocket.get(deviceId);
    if (!socket || socket.readyState !== 1) return 0;

    let offset = 0;
    let frameCount = 0;

    while (offset + 2 <= framedOpus.length) {
      const frameLen = framedOpus.readUInt16BE(offset);
      offset += 2;

      if (offset + frameLen > framedOpus.length) {
        this.logger.warn(`Framed opus truncated at offset ${offset}, expected ${frameLen} bytes`);
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
}
