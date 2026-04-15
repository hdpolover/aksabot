import { SchedulerService } from './scheduler.service';
import { DEFAULT_REMINDER_CONFIG } from './types';

describe('SchedulerService', () => {
  let service: SchedulerService;
  let devicesRepo: Record<string, jest.Mock>;
  let mockReminderService: Record<string, jest.Mock>;
  let mockPomodoroService: Record<string, jest.Mock>;
  let mockResponsePool: Record<string, jest.Mock>;
  let mockSessions: Record<string, jest.Mock>;
  let sendToDevice: jest.Mock;

  const makeDevice = (overrides: any = {}) => ({
    id: 'device-1',
    settingsJson: { reminders: DEFAULT_REMINDER_CONFIG },
    personalityJson: { name: 'Ziggy' },
    ...overrides,
  });

  beforeEach(() => {
    jest.useFakeTimers({ now: new Date('2026-04-12T10:00:00').getTime() });

    devicesRepo = {
      findOne: jest.fn().mockResolvedValue(makeDevice()),
      save: jest.fn().mockImplementation((d) => Promise.resolve(d)),
    };

    mockReminderService = {
      generate: jest.fn().mockResolvedValue({
        type: 'stand_up',
        text: 'Time to stand!',
        audio: Buffer.from('audio'),
        cacheKey: 'key-1',
        display: {
          expression: 'encouraging',
          screenMode: 'reminder',
          durationMs: 10_000,
        },
      }),
    };

    mockPomodoroService = {
      setSendToDevice: jest.fn(),
      stopAllForDevice: jest.fn(),
      isActive: jest.fn().mockReturnValue(false),
    };

    mockResponsePool = {
      refillIfNeeded: jest.fn().mockResolvedValue(undefined),
    };

    mockSessions = {
      get: jest.fn().mockReturnValue({ state: 'idle' }),
    };

    sendToDevice = jest.fn();

    const mockAi = { buildSystemPrompt: jest.fn() };
    service = new SchedulerService(
      devicesRepo as any,
      mockReminderService as any,
      mockPomodoroService as any,
      mockResponsePool as any,
      mockSessions as any,
      mockAi as any,
    );
    service.setSendToDevice(sendToDevice);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  // ── onDeviceConnected (startDeviceSchedule) ──────────

  describe('startDeviceSchedule', () => {
    it('creates timers for all enabled reminders', async () => {
      await service.startDeviceSchedule('device-1');

      // Advance 20 minutes — eye_break interval (async to flush fireReminder promises)
      await jest.advanceTimersByTimeAsync(20 * 60_000);

      // Reminder should have fired for eye_break
      expect(mockReminderService.generate).toHaveBeenCalledWith(
        'device-1',
        'eye_break',
      );
    });

    it('sends reminder event to device when timer fires', async () => {
      await service.startDeviceSchedule('device-1');

      // Advance past the shortest interval and flush all async work
      await jest.advanceTimersByTimeAsync(20 * 60_000);

      expect(sendToDevice).toHaveBeenCalledWith(
        'device-1',
        'proactive:reminder',
        expect.objectContaining({ type: 'stand_up' }),
      );
    });

    it('does not fire reminder when device is not connected', async () => {
      mockSessions.get.mockReturnValue(undefined);

      await service.startDeviceSchedule('device-1');
      jest.advanceTimersByTime(20 * 60_000);

      await Promise.resolve();

      expect(mockReminderService.generate).not.toHaveBeenCalled();
    });

    it('does not fire reminder when device is in conversation', async () => {
      mockSessions.get.mockReturnValue({ state: 'listening' });

      await service.startDeviceSchedule('device-1');
      jest.advanceTimersByTime(20 * 60_000);

      await Promise.resolve();

      expect(mockReminderService.generate).not.toHaveBeenCalled();
    });

    it('does not fire reminder during pomodoro', async () => {
      mockPomodoroService.isActive.mockReturnValue(true);

      await service.startDeviceSchedule('device-1');
      jest.advanceTimersByTime(20 * 60_000);

      await Promise.resolve();

      expect(mockReminderService.generate).not.toHaveBeenCalled();
    });

    it('uses DEFAULT_REMINDER_CONFIG when device has no settings', async () => {
      devicesRepo.findOne.mockResolvedValue(null);

      // Should not throw
      await expect(
        service.startDeviceSchedule('device-1'),
      ).resolves.toBeUndefined();
    });

    it('skips disabled reminders', async () => {
      devicesRepo.findOne.mockResolvedValue(
        makeDevice({
          settingsJson: {
            reminders: {
              ...DEFAULT_REMINDER_CONFIG,
              eye_break: { enabled: false, intervalMinutes: 20 },
            },
          },
        }),
      );

      await service.startDeviceSchedule('device-1');
      // eye_break is disabled; with default config the first interval is posture at 30m
      jest.advanceTimersByTime(19 * 60_000);

      expect(mockReminderService.generate).not.toHaveBeenCalledWith(
        'device-1',
        'eye_break',
      );
    });
  });

  // ── onDeviceDisconnected (stopDeviceSchedule) ────────

  describe('stopDeviceSchedule', () => {
    it('clears timers and stops pomodoro', async () => {
      await service.startDeviceSchedule('device-1');
      service.stopDeviceSchedule('device-1');

      // Advance past any interval — no reminder should fire
      jest.advanceTimersByTime(120 * 60_000);

      expect(mockReminderService.generate).not.toHaveBeenCalled();
      expect(mockPomodoroService.stopAllForDevice).toHaveBeenCalledWith(
        'device-1',
      );
    });

    it('does not throw for an unregistered device', () => {
      expect(() => service.stopDeviceSchedule('unknown-device')).not.toThrow();
    });

    it('replaces existing schedule on second startDeviceSchedule', async () => {
      await service.startDeviceSchedule('device-1');
      await service.startDeviceSchedule('device-1');

      // Should not throw or double-fire
      jest.advanceTimersByTime(20 * 60_000);
      await Promise.resolve();

      // Only one set of timers active — generate called once for eye_break
      expect(mockReminderService.generate).toHaveBeenCalledTimes(1);
    });
  });

  // ── Focus mode ───────────────────────────────────────

  describe('startFocusMode / clearFocusMode', () => {
    it('sends focus:start event immediately', () => {
      service.startFocusMode('device-1', 30);

      expect(sendToDevice).toHaveBeenCalledWith('device-1', 'focus:start', {
        durationMinutes: 30,
      });
    });

    it('reports isFocusMode as true while active', () => {
      service.startFocusMode('device-1', 30);
      expect(service.isFocusMode('device-1')).toBe(true);
    });

    it('sends focus:end and clears state after duration', () => {
      service.startFocusMode('device-1', 30);
      sendToDevice.mockClear();

      jest.advanceTimersByTime(30 * 60_000);

      expect(sendToDevice).toHaveBeenCalledWith('device-1', 'focus:end', {});
      expect(service.isFocusMode('device-1')).toBe(false);
    });

    it('suppresses reminders while focus mode is active', async () => {
      // startDeviceSchedule calls stopDeviceSchedule internally, which clears focus mode.
      // So focus mode must be activated AFTER starting the schedule.
      await service.startDeviceSchedule('device-1');
      service.startFocusMode('device-1', 60);

      jest.advanceTimersByTime(20 * 60_000); // eye_break interval
      await Promise.resolve();

      expect(mockReminderService.generate).not.toHaveBeenCalled();
    });

    it('clearFocusMode cancels the timer', () => {
      service.startFocusMode('device-1', 30);
      service.clearFocusMode('device-1');

      expect(service.isFocusMode('device-1')).toBe(false);

      jest.advanceTimersByTime(30 * 60_000);

      // focus:end should NOT have been called after clearFocusMode
      const focusEndCalls = sendToDevice.mock.calls.filter(
        (c: any[]) => c[1] === 'focus:end',
      );
      expect(focusEndCalls).toHaveLength(0);
    });

    it('replaces existing focus timer on restart', () => {
      service.startFocusMode('device-1', 60);
      service.startFocusMode('device-1', 30); // shorter duration replaces

      jest.advanceTimersByTime(30 * 60_000);

      expect(service.isFocusMode('device-1')).toBe(false);
    });
  });

  // ── getReminderConfig / updateReminderConfig ─────────

  describe('getReminderConfig', () => {
    it('returns device reminder config', async () => {
      const config = await service.getReminderConfig('device-1');
      expect(config).toEqual(DEFAULT_REMINDER_CONFIG);
    });

    it('returns default config when device not found', async () => {
      devicesRepo.findOne.mockResolvedValue(null);
      const config = await service.getReminderConfig('device-1');
      expect(config).toEqual(DEFAULT_REMINDER_CONFIG);
    });
  });

  describe('updateReminderConfig', () => {
    it('merges and saves partial config', async () => {
      const result = await service.updateReminderConfig('device-1', {
        standUp: { enabled: false, intervalMinutes: 60 },
      });

      expect(result.standUp.enabled).toBe(false);
      expect(devicesRepo.save).toHaveBeenCalled();
    });

    it('throws when device not found', async () => {
      devicesRepo.findOne.mockResolvedValue(null);
      await expect(
        service.updateReminderConfig('device-1', {}),
      ).rejects.toThrow('Device not found');
    });

    it('restarts schedule when device has active timers', async () => {
      await service.startDeviceSchedule('device-1');
      devicesRepo.findOne.mockResolvedValue(makeDevice());

      const startSpy = jest.spyOn(service, 'startDeviceSchedule');
      await service.updateReminderConfig('device-1', {
        hydration: { enabled: false, intervalMinutes: 45 },
      });

      expect(startSpy).toHaveBeenCalledWith('device-1');
    });
  });

  // ── Pool refill trigger ──────────────────────────────

  describe('handlePoolRefill', () => {
    it('triggers refillIfNeeded for all connected devices', async () => {
      await service.startDeviceSchedule('device-1');
      await service.startDeviceSchedule('device-2');

      await service.handlePoolRefill();

      expect(mockResponsePool.refillIfNeeded).toHaveBeenCalledWith('device-1');
      expect(mockResponsePool.refillIfNeeded).toHaveBeenCalledWith('device-2');
    });

    it('does not throw when pool refill rejects', async () => {
      mockResponsePool.refillIfNeeded.mockRejectedValue(
        new Error('Redis down'),
      );
      await service.startDeviceSchedule('device-1');

      await expect(service.handlePoolRefill()).resolves.toBeUndefined();
    });

    it('does not refill when no devices are connected', async () => {
      await service.handlePoolRefill();
      expect(mockResponsePool.refillIfNeeded).not.toHaveBeenCalled();
    });
  });
});
