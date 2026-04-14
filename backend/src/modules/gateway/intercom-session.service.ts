import { Injectable, Logger } from '@nestjs/common';
import type WebSocket from 'ws';

/**
 * Tracks active intercom sessions (deviceId → app WebSocket).
 *
 * Shared between IntercomGateway (registers/unregisters the app client)
 * and AudioGateway (pushes device reply audio back to the app), avoiding
 * a circular dependency between the two gateways.
 */
@Injectable()
export class IntercomSessionService {
  private readonly logger = new Logger(IntercomSessionService.name);
  private readonly sessions = new Map<string, WebSocket>();

  register(deviceId: string, socket: WebSocket): void {
    this.sessions.set(deviceId, socket);
    this.logger.log(`Intercom session registered: device ${deviceId}`);
  }

  unregister(deviceId: string): void {
    this.sessions.delete(deviceId);
    this.logger.log(`Intercom session unregistered: device ${deviceId}`);
  }

  hasSession(deviceId: string): boolean {
    const socket = this.sessions.get(deviceId);
    return !!socket && socket.readyState === 1;
  }

  /** Send a JSON event to the app client for this device. */
  sendJsonToApp(deviceId: string, event: string, data: unknown = {}): void {
    const socket = this.sessions.get(deviceId);
    if (!socket || socket.readyState !== 1) return;
    socket.send(JSON.stringify({ event, data }));
  }

  /** Send raw binary bytes (e.g. WAV audio) to the app client for this device. */
  sendBinaryToApp(deviceId: string, buffer: Buffer): void {
    const socket = this.sessions.get(deviceId);
    if (!socket || socket.readyState !== 1) return;
    socket.send(buffer);
  }
}
