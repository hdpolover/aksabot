import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from '../../core/database/entities';
import { ReminderService } from './reminder.service';
import { PomodoroService } from './pomodoro.service';
import { ResponsePoolService } from './response-pool.service';
import { SessionManager } from '../gateway/session.manager';
import {
  DEFAULT_REMINDER_CONFIG,
  type ReminderConfig,
  type ReminderType,
} from './types';

@Injectable()
export class SchedulerService implements OnModuleInit {
  private readonly logger = new Logger(SchedulerService.name);
  private deviceTimers = new Map<string, NodeJS.Timeout[]>();
  private focusMode = new Map<string, NodeJS.Timeout>();

  // Injected later to avoid circular dep with gateway
  private sendToDevice: (
    deviceId: string,
    event: string,
    data: any,
  ) => void = () => {};

  constructor(
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
    private readonly reminderService: ReminderService,
    private readonly pomodoroService: PomodoroService,
    private readonly responsePool: ResponsePoolService,
    private readonly sessions: SessionManager,
  ) {}

  onModuleInit() {
    // Share sendToDevice with pomodoro service
    this.pomodoroService.setSendToDevice(
      (deviceId, event, data) => this.sendToDevice(deviceId, event, data),
    );
  }

  setSendToDevice(fn: (deviceId: string, event: string, data: any) => void) {
    this.sendToDevice = fn;
    this.pomodoroService.setSendToDevice(fn);
  }

  // ── Device connect/disconnect lifecycle ──────────────

  async startDeviceSchedule(deviceId: string): Promise<void> {
    // Clear existing timers
    this.stopDeviceSchedule(deviceId);

    // Get reminder config from device settings
    const device = await this.devicesRepo.findOne({
      where: { id: deviceId },
    });
    const config: ReminderConfig =
      device?.settingsJson?.reminders ?? DEFAULT_REMINDER_CONFIG;

    const timers: NodeJS.Timeout[] = [];

    const scheduleReminder = (
      type: ReminderType,
      enabled: boolean,
      intervalMinutes: number,
    ) => {
      if (!enabled) return;
      timers.push(
        setInterval(
          () => this.fireReminder(deviceId, type),
          intervalMinutes * 60_000,
        ),
      );
    };

    scheduleReminder('stand_up', config.standUp.enabled, config.standUp.intervalMinutes);
    scheduleReminder('hydration', config.hydration.enabled, config.hydration.intervalMinutes);
    scheduleReminder('eye_break', config.eyeBreak.enabled, config.eyeBreak.intervalMinutes);
    scheduleReminder('stretch', config.stretch.enabled, config.stretch.intervalMinutes);
    scheduleReminder('posture', config.posture.enabled, config.posture.intervalMinutes);

    this.deviceTimers.set(deviceId, timers);
    this.logger.log(`Started reminder schedule for device ${deviceId}`);

    // Pool refill is NOT triggered on connect — it happens:
    // 1. Lazily when the first reminder fires (pickLru generates on empty pool)
    // 2. Every 6 hours via cron for connected devices
    // This avoids 10+ Gemini API calls on every reconnect.
  }

  stopDeviceSchedule(deviceId: string): void {
    const timers = this.deviceTimers.get(deviceId) ?? [];
    timers.forEach(clearInterval);
    this.deviceTimers.delete(deviceId);
    this.pomodoroService.stopAllForDevice(deviceId);
    this.clearFocusMode(deviceId);
  }

  // ── Reminder firing ──────────────────────────────────

  private async fireReminder(
    deviceId: string,
    type: ReminderType,
  ): Promise<void> {
    // Suppress if device is busy
    const session = this.sessions.get(deviceId);
    if (!session) return; // device not connected

    if (session.state !== 'idle') return; // in conversation
    if (this.focusMode.has(deviceId)) return; // focus mode active
    if (this.pomodoroService.isActive(deviceId)) return; // pomodoro active

    try {
      const reminder = await this.reminderService.generate(deviceId, type);

      this.sendToDevice(deviceId, 'proactive:reminder', {
        type: reminder.type,
        text: reminder.text,
        cacheKey: reminder.cacheKey,
        display: reminder.display,
      });

      this.logger.debug(`Fired ${type} reminder for device ${deviceId}`);
    } catch (err: any) {
      this.logger.warn(
        `Reminder ${type} failed for ${deviceId}: ${err.message}`,
      );
    }
  }

  // ── Focus mode ───────────────────────────────────────

  startFocusMode(deviceId: string, durationMinutes: number): void {
    this.clearFocusMode(deviceId);

    const timer = setTimeout(() => {
      this.focusMode.delete(deviceId);
      this.sendToDevice(deviceId, 'focus:end', {});
      this.logger.log(`Focus mode ended for device ${deviceId}`);
    }, durationMinutes * 60_000);

    this.focusMode.set(deviceId, timer);
    this.sendToDevice(deviceId, 'focus:start', { durationMinutes });
    this.logger.log(
      `Focus mode started for device ${deviceId} (${durationMinutes}m)`,
    );
  }

  clearFocusMode(deviceId: string): void {
    const timer = this.focusMode.get(deviceId);
    if (timer) {
      clearTimeout(timer);
      this.focusMode.delete(deviceId);
    }
  }

  isFocusMode(deviceId: string): boolean {
    return this.focusMode.has(deviceId);
  }

  // ── Reminder config management ───────────────────────

  async getReminderConfig(deviceId: string): Promise<ReminderConfig> {
    const device = await this.devicesRepo.findOne({
      where: { id: deviceId },
    });
    return device?.settingsJson?.reminders ?? DEFAULT_REMINDER_CONFIG;
  }

  async updateReminderConfig(
    deviceId: string,
    config: Partial<ReminderConfig>,
  ): Promise<ReminderConfig> {
    const device = await this.devicesRepo.findOne({
      where: { id: deviceId },
    });
    if (!device) throw new Error('Device not found');

    const current = device.settingsJson?.reminders ?? DEFAULT_REMINDER_CONFIG;
    const merged = { ...current, ...config };
    device.settingsJson = { ...device.settingsJson, reminders: merged };
    await this.devicesRepo.save(device);

    // Restart schedule with new config
    if (this.deviceTimers.has(deviceId)) {
      await this.startDeviceSchedule(deviceId);
    }

    return merged;
  }

  // ── Background pool refill (every 6 hours) ──────────

  @Cron(CronExpression.EVERY_6_HOURS)
  async handlePoolRefill() {
    // Refill pools for all connected devices
    for (const deviceId of this.deviceTimers.keys()) {
      this.responsePool.refillIfNeeded(deviceId).catch((err) =>
        this.logger.warn(`Pool refill failed for ${deviceId}: ${err.message}`),
      );
    }
  }
}
