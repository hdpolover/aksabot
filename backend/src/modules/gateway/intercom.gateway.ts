import { Inject, Logger } from '@nestjs/common';
import {
  WebSocketGateway,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import type { IncomingMessage } from 'http';
import type WebSocket from 'ws';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from '../../core/database/entities';
import { AUDIO_CODEC } from '../ai/interfaces/tokens';
import type { IAudioCodec } from '../ai/interfaces';
import { AudioGateway } from './audio.gateway';
import { IntercomSessionService } from './intercom-session.service';

interface ClientState {
  userId: string;
  deviceId: string | null;
  pcmBuffer: Buffer;
  started: boolean;
}

/**
 * Real-time voice intercom gateway at /intercom.
 *
 * The Flutter app connects with a JWT in the query string, sends an
 * `intercom:start` JSON event, then streams raw 16kHz/mono/16-bit PCM
 * as binary WebSocket messages.  Each 640-byte chunk (= 320 samples =
 * 20 ms) is encoded to one Opus frame and forwarded to the device.
 * The app signals end by sending `intercom:stop` or closing the socket.
 */
@WebSocketGateway({ path: '/intercom' })
export class IntercomGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  private readonly logger = new Logger(IntercomGateway.name);

  /** 320 samples × 2 bytes = 640 bytes of 16-bit PCM per 20 ms frame */
  private static readonly FRAME_BYTES = 640;

  private readonly clients = new Map<WebSocket, ClientState>();

  constructor(
    private readonly jwtService: JwtService,
    @InjectRepository(Device) private readonly devicesRepo: Repository<Device>,
    private readonly audioGateway: AudioGateway,
    private readonly intercomSessions: IntercomSessionService,
    @Inject(AUDIO_CODEC) private readonly codec: IAudioCodec,
  ) {}

  // ── Connection lifecycle ──────────────────────────────────────────────

  async handleConnection(client: WebSocket, req: IncomingMessage) {
    const url = new URL(req.url ?? '/', 'ws://localhost');
    const token = url.searchParams.get('token');

    if (!token) {
      client.close(1008, 'Missing token');
      return;
    }

    let payload: { sub: string };
    try {
      payload = this.jwtService.verify(token);
    } catch {
      client.close(1008, 'Invalid or expired token');
      return;
    }

    const state: ClientState = {
      userId: payload.sub,
      deviceId: null,
      pcmBuffer: Buffer.alloc(0),
      started: false,
    };
    this.clients.set(client, state);

    client.on('message', (raw: Buffer | string, isBinary: boolean) => {
      this.handleMessage(client, raw, isBinary).catch((err) =>
        this.logger.error(`Intercom message error: ${err.message}`),
      );
    });

    this.logger.log(`Intercom connected: user ${payload.sub}`);
  }

  handleDisconnect(client: WebSocket) {
    const state = this.clients.get(client);
    if (state?.started && state.deviceId) {
      this.flushAndStop(state);
    }
    if (state?.deviceId) {
      this.intercomSessions.unregister(state.deviceId);
    }
    if (state) {
      this.logger.log(`Intercom disconnected: user ${state.userId}`);
    }
    this.clients.delete(client);
  }

  // ── Message handling ──────────────────────────────────────────────────

  private async handleMessage(
    client: WebSocket,
    raw: Buffer | string,
    isBinary: boolean,
  ) {
    const state = this.clients.get(client);
    if (!state) return;

    if (isBinary) {
      this.handlePcmChunk(state, raw as Buffer);
    } else {
      let msg: { event: string; data?: any };
      try {
        msg = JSON.parse(raw as string) as { event: string; data?: any };
      } catch {
        return;
      }

      switch (msg.event) {
        case 'intercom:start':
          await this.handleStart(client, state, msg.data);
          break;
        case 'intercom:stop':
          this.flushAndStop(state);
          break;
      }
    }
  }

  private async handleStart(
    client: WebSocket,
    state: ClientState,
    data: { deviceId?: string },
  ) {
    if (!data?.deviceId) {
      client.send(
        JSON.stringify({
          event: 'error',
          data: { message: 'deviceId required' },
        }),
      );
      return;
    }

    // Verify the requesting user owns this device
    const device = await this.devicesRepo.findOne({
      where: { id: data.deviceId, userId: state.userId },
    });
    if (!device) {
      client.send(
        JSON.stringify({
          event: 'error',
          data: { message: 'Device not found' },
        }),
      );
      return;
    }

    state.deviceId = data.deviceId;
    state.started = true;
    state.pcmBuffer = Buffer.alloc(0);

    // Register so AudioGateway can push device replies back to this client
    this.intercomSessions.register(data.deviceId, client);

    this.audioGateway.sendToDevice(data.deviceId, 'response:start', {
      type: 'intercom',
    });
    client.send(JSON.stringify({ event: 'intercom:ready' }));

    this.logger.log(
      `Intercom started: user ${state.userId} → device ${data.deviceId}`,
    );
  }

  private handlePcmChunk(state: ClientState, chunk: Buffer) {
    if (!state.started || !state.deviceId) return;

    state.pcmBuffer = Buffer.concat([state.pcmBuffer, chunk]);

    while (state.pcmBuffer.length >= IntercomGateway.FRAME_BYTES) {
      const frame = state.pcmBuffer.subarray(0, IntercomGateway.FRAME_BYTES);
      state.pcmBuffer = Buffer.from(
        state.pcmBuffer.subarray(IntercomGateway.FRAME_BYTES),
      );

      try {
        // codec.encode returns [2-byte BE length][opus frame]
        const framedOpus = this.codec.encode(frame);
        if (framedOpus.length > 2) {
          const frameLen = framedOpus.readUInt16BE(0);
          const opusFrame = framedOpus.subarray(2, 2 + frameLen);
          this.audioGateway.sendOpusFrameToDevice(state.deviceId, opusFrame);
        }
      } catch (err: any) {
        this.logger.warn(`Opus encode error: ${err.message}`);
      }
    }
  }

  private flushAndStop(state: ClientState) {
    if (!state.started || !state.deviceId) return;
    this.intercomSessions.unregister(state.deviceId);

    // Flush any partial frame — pad with silence so the encoder gets a full frame
    if (state.pcmBuffer.length > 0) {
      const padded = Buffer.alloc(IntercomGateway.FRAME_BYTES, 0);
      state.pcmBuffer.copy(padded);
      try {
        const framedOpus = this.codec.encode(padded);
        if (framedOpus.length > 2) {
          const frameLen = framedOpus.readUInt16BE(0);
          this.audioGateway.sendOpusFrameToDevice(
            state.deviceId,
            framedOpus.subarray(2, 2 + frameLen),
          );
        }
      } catch {
        /* best-effort */
      }
    }

    this.audioGateway.sendToDevice(state.deviceId, 'response:end', {
      fullText: '',
      cacheKeys: [],
    });

    state.started = false;
    state.pcmBuffer = Buffer.alloc(0);
    this.logger.log(`Intercom stopped: user ${state.userId}`);
  }
}
