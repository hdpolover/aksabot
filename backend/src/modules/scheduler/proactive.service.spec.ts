import { ProactiveService } from './proactive.service';

// Helpers to construct timestamps as milliseconds (required by jest.setSystemTime)
const ts = (iso: string) => new Date(iso).getTime();

describe('ProactiveService', () => {
  let service: ProactiveService;
  let devicesRepo: Record<string, jest.Mock>;
  let mockLlm: { generate: jest.Mock };
  let mockMemories: Record<string, jest.Mock>;
  let mockSessions: Record<string, jest.Mock>;
  let sendToDevice: jest.Mock;

  const DEVICE_ID = 'device-1';

  const makeDevice = (name = 'Ziggy') => ({
    id: DEVICE_ID,
    personalityJson: { name },
  });

  const makeMemories = (facts: string[] = []) =>
    facts.map((fact, i) => ({ id: `m-${i}`, fact }));

  beforeEach(() => {
    jest.useFakeTimers();

    devicesRepo = {
      findOne: jest.fn().mockResolvedValue(makeDevice()),
    };

    mockLlm = {
      generate: jest.fn().mockResolvedValue({ text: 'Good morning!' }),
    };

    mockMemories = {
      getRelevant: jest.fn().mockResolvedValue([]),
    };

    mockSessions = {
      get: jest.fn().mockReturnValue({ state: 'idle' }),
    };

    sendToDevice = jest.fn();

    const mockMoodJournal = { getRecentMoods: jest.fn().mockResolvedValue([]) };
    service = new ProactiveService(
      devicesRepo as any,
      mockLlm as any,
      mockMemories as any,
      mockSessions as any,
      mockMoodJournal as any,
    );
    service.setSendToDevice(sendToDevice);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  // ── checkGreeting (time-aware) ───────────────────────

  describe('checkGreeting', () => {
    it('returns a greeting on first call of the day', async () => {
      const result = await service.checkGreeting(DEVICE_ID);
      expect(result).toBe('Good morning!');
      expect(mockLlm.generate).toHaveBeenCalledTimes(1);
    });

    it('returns a reconnect greeting on subsequent calls within the same day', async () => {
      await service.checkGreeting(DEVICE_ID);
      const second = await service.checkGreeting(DEVICE_ID);
      expect(second).toBe('Good morning!');
      expect(mockLlm.generate).toHaveBeenCalledTimes(2);
    });

    it('generates a new greeting the next day', async () => {
      jest.setSystemTime(ts('2026-04-10T09:00:00'));
      await service.checkGreeting(DEVICE_ID);

      jest.setSystemTime(ts('2026-04-11T09:00:00'));
      const result = await service.checkGreeting(DEVICE_ID);

      expect(result).toBe('Good morning!');
      expect(mockLlm.generate).toHaveBeenCalledTimes(2);
    });

    it('includes "morning" in prompt before noon', async () => {
      jest.setSystemTime(ts('2026-04-10T08:00:00'));

      await service.checkGreeting(DEVICE_ID);

      const userContent: string = mockLlm.generate.mock.calls[0][1][0].content;
      expect(userContent).toContain('morning');
    });

    it('includes "afternoon" in prompt between 12 and 17', async () => {
      jest.setSystemTime(ts('2026-04-10T14:00:00'));

      await service.checkGreeting(DEVICE_ID);

      const userContent: string = mockLlm.generate.mock.calls[0][1][0].content;
      expect(userContent).toContain('afternoon');
    });

    it('includes "evening" in prompt between 17 and 21', async () => {
      jest.setSystemTime(ts('2026-04-10T19:00:00'));

      await service.checkGreeting(DEVICE_ID);

      const userContent: string = mockLlm.generate.mock.calls[0][1][0].content;
      expect(userContent).toContain('evening');
    });

    it('includes "night" in prompt after 21:00', async () => {
      jest.setSystemTime(ts('2026-04-10T22:00:00'));

      await service.checkGreeting(DEVICE_ID);

      const userContent: string = mockLlm.generate.mock.calls[0][1][0].content;
      expect(userContent).toContain('night');
    });

    it('passes memory context to LLM when memories exist', async () => {
      mockMemories.getRelevant.mockResolvedValue(
        makeMemories(['user prefers dark mode', 'working on Aksabot']),
      );

      await service.checkGreeting(DEVICE_ID);

      const userContent: string = mockLlm.generate.mock.calls[0][1][0].content;
      expect(userContent).toContain('user prefers dark mode');
      expect(userContent).toContain('working on Aksabot');
    });

    it('uses hardcoded bot name "Aksa" in the prompt', async () => {
      await service.checkGreeting(DEVICE_ID);

      const promptArg: string = mockLlm.generate.mock.calls[0][0];
      expect(promptArg).toContain('Aksa');
    });

    it('returns null when LLM throws', async () => {
      mockLlm.generate.mockRejectedValue(new Error('API failure'));

      const result = await service.checkGreeting(DEVICE_ID);
      expect(result).toBeNull();
    });
  });

  // ── recordActivity / trackActivity ──────────────────

  describe('recordActivity', () => {
    it('records last activity without throwing', () => {
      expect(() => service.recordActivity(DEVICE_ID)).not.toThrow();
    });

    it('resets the idle timer when activity is recorded', async () => {
      jest.setSystemTime(ts('2026-04-10T10:00:00'));
      service.recordActivity(DEVICE_ID);

      // Advance 3+ hours — should be considered idle
      jest.setSystemTime(ts('2026-04-10T13:05:00'));

      await service.checkIdleNudges();
      expect(sendToDevice).toHaveBeenCalledWith(
        DEVICE_ID,
        'proactive:nudge',
        expect.objectContaining({ text: expect.any(String) }),
      );

      sendToDevice.mockClear();

      // Record new activity (resets the clock inside the map to the current fake time)
      service.recordActivity(DEVICE_ID);

      // Check again immediately — not enough idle time has passed
      await service.checkIdleNudges();
      expect(sendToDevice).not.toHaveBeenCalled();
    });
  });

  // ── generateIdleNudge (checkIdleNudges) ─────────────

  describe('checkIdleNudges', () => {
    beforeEach(() => {
      jest.setSystemTime(ts('2026-04-10T10:00:00'));
      service.recordActivity(DEVICE_ID);
    });

    it('sends nudge after 3+ hours of idle during work hours', async () => {
      jest.setSystemTime(ts('2026-04-10T13:05:00')); // 3h5m later, within work hours

      await service.checkIdleNudges();

      expect(sendToDevice).toHaveBeenCalledWith(
        DEVICE_ID,
        'proactive:nudge',
        expect.objectContaining({
          display: expect.objectContaining({ expression: 'gentle' }),
        }),
      );
    });

    it('does not nudge before 3 hours idle', async () => {
      jest.setSystemTime(ts('2026-04-10T12:00:00')); // only 2 hours

      await service.checkIdleNudges();

      expect(sendToDevice).not.toHaveBeenCalled();
    });

    it('does not nudge outside work hours (after 18:00)', async () => {
      jest.setSystemTime(ts('2026-04-10T20:00:00')); // past work hours end

      await service.checkIdleNudges();

      expect(sendToDevice).not.toHaveBeenCalled();
    });

    it('does not nudge when device is not idle', async () => {
      mockSessions.get.mockReturnValue({ state: 'listening' });
      jest.setSystemTime(ts('2026-04-10T13:05:00'));

      await service.checkIdleNudges();

      expect(sendToDevice).not.toHaveBeenCalled();
    });

    it('does not nudge when session is not found', async () => {
      mockSessions.get.mockReturnValue(undefined);
      jest.setSystemTime(ts('2026-04-10T13:05:00'));

      await service.checkIdleNudges();

      expect(sendToDevice).not.toHaveBeenCalled();
    });

    it('resets activity after sending nudge to prevent repeated nudges', async () => {
      jest.setSystemTime(ts('2026-04-10T13:05:00'));

      await service.checkIdleNudges();
      sendToDevice.mockClear();

      // Immediately check again — activity was reset to now, so no second nudge
      await service.checkIdleNudges();

      expect(sendToDevice).not.toHaveBeenCalled();
    });
  });

  // ── generateEndOfDay (handleEndOfDay) ────────────────

  describe('handleEndOfDay', () => {
    beforeEach(() => {
      service.recordActivity(DEVICE_ID);
    });

    it('sends end-of-day briefing to active idle devices', async () => {
      mockLlm.generate.mockResolvedValue({ text: 'Great work today! What did you accomplish?' });

      await service.handleEndOfDay();

      expect(sendToDevice).toHaveBeenCalledWith(
        DEVICE_ID,
        'proactive:briefing',
        expect.objectContaining({
          type: 'end_of_day',
          text: 'Great work today! What did you accomplish?',
          display: expect.objectContaining({ expression: 'calm' }),
        }),
      );
    });

    it('includes memory context in the LLM prompt', async () => {
      mockMemories.getRelevant.mockResolvedValue(
        makeMemories(['working on NestJS backend', 'debugging WebSocket']),
      );

      await service.handleEndOfDay();

      const userContent: string = mockLlm.generate.mock.calls[0][1][0].content;
      expect(userContent).toContain('working on NestJS backend');
    });

    it('uses hardcoded bot name "Aksa" in the prompt', async () => {
      await service.handleEndOfDay();

      const promptArg: string = mockLlm.generate.mock.calls[0][0];
      expect(promptArg).toContain('Aksa');
    });

    it('skips devices where session is not idle', async () => {
      mockSessions.get.mockReturnValue({ state: 'thinking' });

      await service.handleEndOfDay();

      expect(sendToDevice).not.toHaveBeenCalled();
    });

    it('skips devices with no active session', async () => {
      mockSessions.get.mockReturnValue(undefined);

      await service.handleEndOfDay();

      expect(sendToDevice).not.toHaveBeenCalled();
    });

    it('does not throw when LLM fails for a device', async () => {
      mockLlm.generate.mockRejectedValue(new Error('LLM timeout'));

      await expect(service.handleEndOfDay()).resolves.toBeUndefined();
    });
  });

  // ── clearDevice ───────────────────────────────────────

  describe('clearDevice', () => {
    it('preserves greeting date tracking across disconnect — reconnect greeting same day', async () => {
      jest.setSystemTime(ts('2026-04-10T09:00:00'));
      await service.checkGreeting(DEVICE_ID);

      service.clearDevice(DEVICE_ID);

      // Same day — should generate a reconnect greeting (not first-of-day)
      const result = await service.checkGreeting(DEVICE_ID);
      expect(result).toBe('Good morning!');
      expect(mockLlm.generate).toHaveBeenCalledTimes(2);
    });

    it('removes activity tracking so idle nudge is not fired', async () => {
      jest.setSystemTime(ts('2026-04-10T10:00:00'));
      service.recordActivity(DEVICE_ID);

      service.clearDevice(DEVICE_ID);

      // Advance 3+ hours — but activity map was cleared, nothing to check
      jest.setSystemTime(ts('2026-04-10T13:05:00'));
      await service.checkIdleNudges();

      expect(sendToDevice).not.toHaveBeenCalledWith(DEVICE_ID, 'proactive:nudge', expect.anything());
    });
  });
});
