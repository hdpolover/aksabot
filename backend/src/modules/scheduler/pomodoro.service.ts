import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import type { PomodoroState } from './types';
import { ReminderService } from './reminder.service';

export interface PomodoroInfo {
  active: boolean;
  phase?: string;
  cycle?: number;
  phaseStartedAt?: Date;
  durationMinutes?: number;
}

@Injectable()
export class PomodoroService {
  private readonly logger = new Logger(PomodoroService.name);
  private sessions = new Map<string, PomodoroState>();

  // Injected later by SchedulerService to avoid circular dep
  private sendToDevice: (
    deviceId: string,
    event: string,
    data: any,
  ) => void = () => {};

  constructor(private readonly reminderService: ReminderService) {}

  setSendToDevice(fn: (deviceId: string, event: string, data: any) => void) {
    this.sendToDevice = fn;
  }

  async start(deviceId: string): Promise<PomodoroInfo> {
    // Stop existing if any
    this.stop(deviceId);

    const now = new Date();
    const state: PomodoroState = {
      cycle: 1,
      phase: 'focus',
      startedAt: now,
      phaseStartedAt: now,
      focusMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 15,
      cyclesBeforeLongBreak: 4,
      timer: null,
    };

    this.sessions.set(deviceId, state);
    this.scheduleTransition(deviceId, state.focusMinutes);

    this.sendToDevice(deviceId, 'proactive:pomodoro', {
      action: 'start',
      phase: 'focus',
      cycle: 1,
      durationMinutes: 25,
    });

    this.logger.log(`Pomodoro started for device ${deviceId}`);
    return this.getInfo(deviceId);
  }

  async transition(deviceId: string): Promise<void> {
    const state = this.sessions.get(deviceId);
    if (!state) return;

    if (state.phase === 'focus') {
      // Switch to break
      const isLongBreak =
        state.cycle % state.cyclesBeforeLongBreak === 0;
      state.phase = isLongBreak ? 'long_break' : 'short_break';
      const breakMinutes = isLongBreak
        ? state.longBreakMinutes
        : state.shortBreakMinutes;
      state.phaseStartedAt = new Date();

      this.sendToDevice(deviceId, 'proactive:pomodoro', {
        action: 'break',
        phase: state.phase,
        cycle: state.cycle,
        durationMinutes: breakMinutes,
      });

      // Send audio reminder
      this.reminderService
        .generatePomodoro(deviceId, state)
        .then((reminder) => {
          this.sendToDevice(deviceId, 'proactive:reminder', {
            type: reminder.type,
            text: reminder.text,
            cacheKey: reminder.cacheKey,
            display: reminder.display,
          });
          // Send audio as binary (handled by gateway)
        })
        .catch((err) =>
          this.logger.warn(`Pomodoro reminder failed: ${err.message}`),
        );

      this.scheduleTransition(deviceId, breakMinutes);
    } else {
      // Switch to focus
      state.cycle++;
      state.phase = 'focus';
      state.phaseStartedAt = new Date();

      this.sendToDevice(deviceId, 'proactive:pomodoro', {
        action: 'focus',
        phase: 'focus',
        cycle: state.cycle,
        durationMinutes: state.focusMinutes,
      });

      this.reminderService
        .generatePomodoro(deviceId, state)
        .then((reminder) => {
          this.sendToDevice(deviceId, 'proactive:reminder', {
            type: reminder.type,
            text: reminder.text,
            cacheKey: reminder.cacheKey,
            display: reminder.display,
          });
        })
        .catch((err) =>
          this.logger.warn(`Pomodoro reminder failed: ${err.message}`),
        );

      this.scheduleTransition(deviceId, state.focusMinutes);
    }
  }

  stop(deviceId: string): void {
    const state = this.sessions.get(deviceId);
    if (!state) return;

    if (state.timer) clearTimeout(state.timer);
    this.sessions.delete(deviceId);

    this.sendToDevice(deviceId, 'proactive:pomodoro', { action: 'stop' });
    this.logger.log(`Pomodoro stopped for device ${deviceId}`);
  }

  getInfo(deviceId: string): PomodoroInfo {
    const state = this.sessions.get(deviceId);
    if (!state) return { active: false };

    const durationMinutes =
      state.phase === 'focus'
        ? state.focusMinutes
        : state.phase === 'long_break'
          ? state.longBreakMinutes
          : state.shortBreakMinutes;

    return {
      active: true,
      phase: state.phase,
      cycle: state.cycle,
      phaseStartedAt: state.phaseStartedAt,
      durationMinutes,
    };
  }

  isActive(deviceId: string): boolean {
    return this.sessions.has(deviceId);
  }

  stopAllForDevice(deviceId: string): void {
    this.stop(deviceId);
  }

  private scheduleTransition(deviceId: string, minutes: number) {
    const state = this.sessions.get(deviceId);
    if (!state) return;

    if (state.timer) clearTimeout(state.timer);
    state.timer = setTimeout(() => {
      this.transition(deviceId);
    }, minutes * 60_000);
  }
}
