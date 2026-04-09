import { Inject, Logger, OnModuleInit, forwardRef } from '@nestjs/common';
import {
  WebSocketGateway,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import type { IncomingMessage } from 'http';
import type WebSocket from 'ws';
import { AuthService } from '../auth/auth.service';
import { AiService } from '../ai/ai.service';
import { MemoriesService } from '../memories/memories.service';
import { SchedulerService } from '../scheduler/scheduler.service';
import { ProactiveService } from '../scheduler/proactive.service';
import { SessionManager } from './session.manager';
import { ConversationPersistence } from './conversation.persistence';
import type { SttResult } from '../ai/interfaces';

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

  constructor(
    private readonly authService: AuthService,
    private readonly aiService: AiService,
    private readonly memoriesService: MemoriesService,
    @Inject(forwardRef(() => SchedulerService))
    private readonly scheduler: SchedulerService,
    @Inject(forwardRef(() => ProactiveService))
    private readonly proactive: ProactiveService,
    private readonly sessions: SessionManager,
    private readonly persistence: ConversationPersistence,
  ) {}

  onModuleInit() {
    // Give the scheduler and proactive services a way to push events
    const sender = (deviceId: string, event: string, data: any) =>
      this.sendToDevice(deviceId, event, data);
    this.scheduler.setSendToDevice(sender);
    this.proactive.setSendToDevice(sender);
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

    this.logger.log(`Device ${device.id} (${device.name}) connected`);

    // Async setup (non-blocking)
    this.persistence.updateLastSeen(device.id).catch(() => {});
    this.scheduler.startDeviceSchedule(device.id).catch((err) =>
      this.logger.warn(`Scheduler start failed: ${err.message}`),
    );
  }

  handleDisconnect(client: WebSocket) {
    const deviceId = this.socketToDevice.get(client);
    if (!deviceId) return;

    const session = this.sessions.get(deviceId);
    if (session?.conversationId) {
      this.endConversation(deviceId);
    }

    this.scheduler.stopDeviceSchedule(deviceId);
    this.proactive.clearDevice(deviceId);
    this.sessions.remove(deviceId);
    this.socketToDevice.delete(client);
    this.deviceToSocket.delete(deviceId);
    this.logger.log(`Device ${deviceId} disconnected`);
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
          this.onAudioStart(deviceId).catch((err) =>
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
        default:
          this.logger.warn(`Unknown event: ${msg.event}`);
      }
    } catch {
      this.logger.warn(`Invalid JSON from device ${deviceId}`);
    }
  }

  // ── Recording handlers ────────────────────────────────────────

  private async onAudioStart(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

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

      // Check for morning briefing (first interaction of the day)
      this.proactive.checkMorningBriefing(deviceId).then((briefing) => {
        if (briefing) {
          this.sendToDevice(deviceId, 'proactive:briefing', {
            type: 'morning',
            text: briefing,
          });
        }
      }).catch(() => {});
    }

    session.interrupted = false;
    session.state = 'listening';

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
      this.logger.error(`STT error for ${deviceId}: ${err.message}`);
      this.sendToDevice(deviceId, 'error', {
        code: 'STT_ERROR',
        message: 'Speech recognition failed',
      });
      session.state = 'idle';
      this.sendToDevice(deviceId, 'state:update', { state: 'idle' });
    });

    this.sendToDevice(deviceId, 'state:update', { state: 'listening' });
  }

  private onAudioChunk(deviceId: string, opusData: Buffer) {
    const session = this.sessions.get(deviceId);
    if (!session?.sttStream) return;

    try {
      const pcm = this.aiService.decodeAudio(opusData);
      session.sttStream.write(pcm);
    } catch (err: any) {
      this.logger.error(`Decode error for ${deviceId}: ${err.message}`);
    }
  }

  private onAudioEnd(deviceId: string) {
    const session = this.sessions.get(deviceId);
    if (!session?.sttStream) return;
    session.sttStream.end();
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

    // Get personality and history
    const device = await this.persistence.getDevice(deviceId);
    const personality = device?.personalityJson ?? {};

    const allHistory = session.conversationId
      ? await this.persistence.getRecentHistory(session.conversationId)
      : [];
    // Exclude the current user message (last in history) from context
    const history = allHistory.slice(0, -1);

    // Fetch relevant memories
    const memories = await this.memoriesService.getRelevant(deviceId);

    // Bump access on used memories
    if (memories.length > 0) {
      this.memoriesService
        .bumpAccessed(memories.map((m) => m.id))
        .catch((err) =>
          this.logger.warn(`Memory bump failed: ${err.message}`),
        );
    }

    // Run streaming pipeline
    try {
      await this.runPipeline(deviceId, result.transcript, personality, memories, history);
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

    this.sessions.resetIdleTimer(deviceId, () => {
      this.endConversation(deviceId);
    });
  }

  private async runPipeline(
    deviceId: string,
    transcript: string,
    personality: Record<string, any>,
    memories: { fact: string; category: string }[],
    history: { role: string; content: string }[],
  ) {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    const pipeline = this.aiService.processTranscript(
      transcript,
      personality,
      memories,
      history,
    );

    let started = false;
    let fullResponseText = '';
    let cacheKeys: { hash: string; sentence: string }[] = [];

    for await (const event of pipeline) {
      if (this.sessions.isInterrupted(deviceId)) break;

      if (event.type === 'text') {
        this.sendToDevice(deviceId, 'response:text', {
          text: event.text,
          isFinal: false,
        });
      } else if (event.type === 'audio') {
        if (!started) {
          this.sendToDevice(deviceId, 'response:start', { type: 'audio' });
          session.state = 'speaking';
          this.sendToDevice(deviceId, 'state:update', { state: 'speaking' });
          started = true;
        }
        this.sendBinaryToDevice(deviceId, event.data);
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

  private sendJson(client: WebSocket, event: string, data: any) {
    if (client.readyState !== 1) return;
    client.send(JSON.stringify({ event, data }));
  }

  private reject(client: WebSocket, reason: string) {
    this.sendJson(client, 'error', { code: 'AUTH_FAILED', message: reason });
    client.close(4001, reason);
  }

  private extractDeviceToken(req: IncomingMessage): string | null {
    const auth = req.headers['authorization'];
    if (!auth) return null;
    const match = auth.match(/^DeviceToken\s+(.+)$/i);
    return match?.[1] ?? null;
  }
}
