import { Injectable } from '@nestjs/common';
import type { SttStream } from '../ai/interfaces';

export interface BatteryHistoryEntry {
  timestamp: number; // Unix ms
  percent: number;   // 0-100 or 255
  mv: number;
  charging: boolean;
}

export interface DeviceSession {
  deviceId: string;
  userId: string;
  conversationId: string | null;
  state: 'idle' | 'listening' | 'thinking' | 'speaking';
  sttStream: SttStream | null;
  /** Watchdog timer: fires if no audio chunks arrive for too long, ending the STT stream cleanly. */
  sttIdleTimer: ReturnType<typeof setTimeout> | null;
  interrupted: boolean;
  idleTimer: ReturnType<typeof setTimeout> | null;
  /** Audio format for current recording session. 'opus' (default, ESP32) or 'pcm16' (web simulator). */
  audioFormat: 'opus' | 'pcm16';
  /** Language the device is configured to use. Drives STT primary language + LLM response language. */
  language: 'en' | 'id';
  /** Walkie-talkie: true while device is sending a voice reply back to the app. */
  intercomReply: boolean;
  /** Accumulated raw Opus frames from the device during an intercom reply. */
  intercomFrames: Buffer[];
  /** Battery level reported by the device. 0-100 = percentage, 255 = USB powered/charging, undefined = unknown. */
  batteryPercent?: number;
  /** Raw battery voltage in millivolts (after divider compensation). */
  batteryMv?: number;
  /** Whether the device is currently charging (USB or voltage-trend based). */
  batteryCharging?: boolean;
  /** Rolling battery history — last 24h of readings, one per minute. */
  batteryHistory: BatteryHistoryEntry[];
  /** Estimated minutes remaining from firmware discharge rate. */
  batteryMinutesRemaining?: number;
  /** Current display mode reported by the device. 'clock' suppresses proactive events and audio. */
  displayMode?: string;
  /** Set by silent reconnect:back — suppresses the connection greeting. */
  skipGreeting?: boolean;
}

@Injectable()
export class SessionManager {
  private sessions = new Map<string, DeviceSession>();

  /** Default idle timeout before ending a conversation (5 minutes). */
  private readonly IDLE_TIMEOUT_MS = 5 * 60 * 1000;

  create(
    deviceId: string,
    userId: string,
    language: 'en' | 'id' = 'en',
  ): DeviceSession {
    const session: DeviceSession = {
      deviceId,
      userId,
      conversationId: null,
      state: 'idle',
      sttStream: null,
      sttIdleTimer: null,
      interrupted: false,
      idleTimer: null,
      audioFormat: 'opus',
      language,
      intercomReply: false,
      intercomFrames: [],
      batteryHistory: [],
    };
    this.sessions.set(deviceId, session);
    return session;
  }

  setLanguage(deviceId: string, language: 'en' | 'id'): void {
    const session = this.sessions.get(deviceId);
    if (session) session.language = language;
  }

  setDisplayMode(deviceId: string, mode: string): void {
    const session = this.sessions.get(deviceId);
    if (session) session.displayMode = mode;
  }

  /** Returns true when the device is in clock mode — proactive events and audio should be suppressed. */
  isClockMode(deviceId: string): boolean {
    return this.sessions.get(deviceId)?.displayMode === 'clock';
  }

  get(deviceId: string): DeviceSession | undefined {
    return this.sessions.get(deviceId);
  }

  remove(deviceId: string): void {
    const session = this.sessions.get(deviceId);
    if (session) {
      this.clearIdleTimer(session);
      this.clearSttIdleTimer(session);
      session.sttStream?.destroy();
    }
    this.sessions.delete(deviceId);
  }

  /** Start (or reset) the per-stream watchdog. If no audio arrives within ms, calls onTimeout. */
  resetSttIdleTimer(deviceId: string, ms: number, onTimeout: () => void): void {
    const session = this.sessions.get(deviceId);
    if (!session) return;
    this.clearSttIdleTimer(session);
    session.sttIdleTimer = setTimeout(onTimeout, ms);
  }

  clearSttIdleTimer(deviceId: string): void;
  clearSttIdleTimer(session: DeviceSession): void;
  clearSttIdleTimer(arg: string | DeviceSession): void {
    const session = typeof arg === 'string' ? this.sessions.get(arg) : arg;
    if (!session) return;
    if (session.sttIdleTimer) {
      clearTimeout(session.sttIdleTimer);
      session.sttIdleTimer = null;
    }
  }

  setState(deviceId: string, state: DeviceSession['state']): void {
    const session = this.sessions.get(deviceId);
    if (session) session.state = state;
  }

  setConversation(deviceId: string, conversationId: string): void {
    const session = this.sessions.get(deviceId);
    if (session) session.conversationId = conversationId;
  }

  markInterrupted(deviceId: string): void {
    const session = this.sessions.get(deviceId);
    if (session) session.interrupted = true;
  }

  isInterrupted(deviceId: string): boolean {
    return this.sessions.get(deviceId)?.interrupted ?? false;
  }

  clearInterrupted(deviceId: string): void {
    const session = this.sessions.get(deviceId);
    if (session) session.interrupted = false;
  }

  /**
   * Reset the idle timer. Called after each exchange completes.
   * When it fires, the onTimeout callback should end the conversation.
   */
  resetIdleTimer(deviceId: string, onTimeout: () => void): void {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    this.clearIdleTimer(session);
    session.idleTimer = setTimeout(() => {
      onTimeout();
    }, this.IDLE_TIMEOUT_MS);
  }

  private clearIdleTimer(session: DeviceSession): void {
    if (session.idleTimer) {
      clearTimeout(session.idleTimer);
      session.idleTimer = null;
    }
  }
}
