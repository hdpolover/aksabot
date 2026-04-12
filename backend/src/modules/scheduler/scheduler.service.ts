import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from '../../core/database/entities';
import { ReminderService } from './reminder.service';
import { PomodoroService } from './pomodoro.service';
import { ResponsePoolService } from './response-pool.service';
import { SessionManager } from '../gateway/session.manager';
import { AiService } from '../ai/ai.service';
import {
  DEFAULT_REMINDER_CONFIG,
  type ReminderConfig,
  type ReminderType,
} from './types';

@Injectable()
export class SchedulerService implements OnModuleInit {
  private readonly logger = new Logger(SchedulerService.name);
  private deviceTimers = new Map<string, NodeJS.Timeout[]>();
  private contextSyncTimers = new Map<string, NodeJS.Timeout>();
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
    private readonly ai: AiService,
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

    // Start context sync (time + weather push to device)
    this.startContextSync(deviceId).catch((err) =>
      this.logger.warn(`Context sync start failed for ${deviceId}: ${err.message}`),
    );
  }

  stopDeviceSchedule(deviceId: string): void {
    const timers = this.deviceTimers.get(deviceId) ?? [];
    timers.forEach(clearInterval);
    this.deviceTimers.delete(deviceId);

    const ctxTimer = this.contextSyncTimers.get(deviceId);
    if (ctxTimer) {
      clearInterval(ctxTimer);
      this.contextSyncTimers.delete(deviceId);
    }

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

    // Enforce work hours — only fire during configured work hours
    const device = await this.devicesRepo.findOne({ where: { id: deviceId } });
    const remConfig = device?.settingsJson?.reminders ?? {};
    const workStart = remConfig.workHoursStart ?? 9;
    const workEnd = remConfig.workHoursEnd ?? 18;
    const hour = new Date().getHours();
    if (hour < workStart || hour >= workEnd) return;

    try {
      const reminder = await this.reminderService.generate(deviceId, type);

      this.sendToDevice(deviceId, 'proactive:reminder', {
        type: reminder.type,
        text: reminder.text,
        cacheKey: reminder.cacheKey,
        durationMs: reminder.display.durationMs ?? 8000,
        expression: reminder.display.expression,
        screenMode: reminder.display.screenMode,
        countdownSeconds: reminder.display.countdownSeconds,
      });

      this.logger.debug(`Fired ${type} reminder for device ${deviceId}`);
    } catch (err: any) {
      this.logger.warn(
        `Reminder ${type} failed for ${deviceId}: ${err.message}`,
      );
    }
  }

  // ── Context sync (time + weather → device) ───────────

  private static readonly CONTEXT_SYNC_INTERVAL_MS = 10 * 60 * 1000; // 10 min

  private async startContextSync(deviceId: string): Promise<void> {
    // Refresh weather first (so we have data for the initial sync)
    const device = await this.devicesRepo.findOne({ where: { id: deviceId } });
    const settings = device?.settingsJson ?? {};
    if (settings.integrations_weather && settings.latitude && settings.longitude) {
      await this.ai.refreshWeather(settings.latitude, settings.longitude);
    }

    // Send immediately on connect
    this.sendContextSync(deviceId);

    // Then every 10 minutes
    const timer = setInterval(() => {
      this.sendContextSync(deviceId);
    }, SchedulerService.CONTEXT_SYNC_INTERVAL_MS);
    this.contextSyncTimers.set(deviceId, timer);

    this.logger.debug(`Context sync started for device ${deviceId}`);
  }

  private sendContextSync(deviceId: string): void {
    const session = this.sessions.get(deviceId);
    if (!session) return;

    const device = this.devicesRepo.findOne({ where: { id: deviceId } }).then((dev) => {
      const settings = dev?.settingsJson ?? {};
      const tz = settings.timezone as string | undefined;
      const { time, date } = this.ai.formatTimeForDevice(tz);

      const payload: Record<string, any> = { time, date };

      if (settings.integrations_weather) {
        // Refresh weather in background (cached, won't re-fetch if fresh)
        if (settings.latitude && settings.longitude) {
          this.ai.refreshWeather(settings.latitude, settings.longitude).catch(() => {});
        }

        const weather = this.ai.getWeatherData();
        if (weather) {
          payload.weather = weather.description;
          payload.temp = weather.temp;
          payload.humidity = weather.humidity;
          payload.weatherCode = weather.weatherCode;
        }
      }

      this.sendToDevice(deviceId, 'context:sync', payload);
      this.logger.debug(`Context sync sent to ${deviceId}: ${time}, ${payload.weather ?? 'no weather'}`);
    }).catch((err: any) => {
      this.logger.warn(`Context sync failed for ${deviceId}: ${err.message}`);
    });
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
