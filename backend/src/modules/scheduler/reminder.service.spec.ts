import { ReminderService } from './reminder.service';
import { REMINDER_DISPLAY } from './types';

describe('ReminderService', () => {
  let service: ReminderService;
  let mockResponsePool: Record<string, jest.Mock>;
  let mockAiService: Record<string, jest.Mock>;
  let mockTts: { synthesize: jest.Mock };
  let mockTtsCache: { get: jest.Mock; set: jest.Mock };
  let mockCodec: { encode: jest.Mock };

  const DEVICE_ID = 'device-1';
  const PCM_BUFFER = Buffer.from('pcm-audio');
  const ENCODED_BUFFER = Buffer.from('opus-audio');
  const CACHE_KEY = 'sha256-abc123';

  const makePoolEntry = (overrides: any = {}) => ({
    id: 'rp-1',
    text: 'Time to stand up!',
    ttsCacheKey: null,
    useCount: 1,
    ...overrides,
  });

  beforeEach(() => {
    mockResponsePool = {
      pickLru: jest.fn().mockResolvedValue(makePoolEntry()),
      updateCacheKey: jest.fn().mockResolvedValue(undefined),
    };

    mockAiService = {
      ttsCacheKey: jest.fn().mockReturnValue(CACHE_KEY),
    };

    mockTts = {
      synthesize: jest.fn().mockResolvedValue(PCM_BUFFER),
    };

    mockTtsCache = {
      get: jest.fn().mockResolvedValue(null), // cache miss by default
      set: jest.fn().mockResolvedValue(undefined),
    };

    mockCodec = {
      encode: jest.fn().mockReturnValue(ENCODED_BUFFER),
    };

    service = new ReminderService(
      mockResponsePool as any,
      mockAiService as any,
      mockTts as any,
      mockTtsCache as any,
      mockCodec as any,
    );
  });

  // ── generate (pool pick + TTS) ───────────────────────

  describe('generate', () => {
    it('returns a reminder payload from the pool', async () => {
      const result = await service.generate(DEVICE_ID, 'stand_up');

      expect(result.type).toBe('stand_up');
      expect(result.text).toBe('Time to stand up!');
      expect(result.audio).toEqual(ENCODED_BUFFER);
      expect(result.display).toEqual(REMINDER_DISPLAY['stand_up']);
    });

    it('picks from the response pool using the given type', async () => {
      await service.generate(DEVICE_ID, 'hydration');

      expect(mockResponsePool.pickLru).toHaveBeenCalledWith(DEVICE_ID, 'hydration');
    });

    it('synthesizes audio via TTS on cache miss', async () => {
      await service.generate(DEVICE_ID, 'stand_up');

      expect(mockTts.synthesize).toHaveBeenCalledWith('Time to stand up!', {});
      expect(mockCodec.encode).toHaveBeenCalledWith(PCM_BUFFER);
    });

    it('stores newly synthesized audio in TTS cache', async () => {
      await service.generate(DEVICE_ID, 'stand_up');

      // set is called non-blocking; flush microtasks
      await Promise.resolve();

      expect(mockTtsCache.set).toHaveBeenCalledWith(CACHE_KEY, ENCODED_BUFFER);
    });

    it('returns cached audio when existing ttsCacheKey hits cache', async () => {
      const cachedAudio = Buffer.from('cached-opus');
      mockResponsePool.pickLru.mockResolvedValue(makePoolEntry({ ttsCacheKey: 'existing-key' }));
      mockTtsCache.get.mockResolvedValue(cachedAudio);

      const result = await service.generate(DEVICE_ID, 'stand_up');

      expect(result.audio).toEqual(cachedAudio);
      expect(result.cacheKey).toBe('existing-key');
      expect(mockTts.synthesize).not.toHaveBeenCalled();
    });

    it('falls back to synthesis when existing cache key is a miss', async () => {
      mockResponsePool.pickLru.mockResolvedValue(makePoolEntry({ ttsCacheKey: 'stale-key' }));
      mockTtsCache.get.mockResolvedValue(null); // both key lookups miss

      const result = await service.generate(DEVICE_ID, 'stand_up');

      expect(mockTts.synthesize).toHaveBeenCalled();
      expect(result.audio).toEqual(ENCODED_BUFFER);
    });

    it('returns audio from hash-based cache when no ttsCacheKey but hash hits', async () => {
      // Pool entry has no existing ttsCacheKey, so getOrSynthesizeAudio skips the first
      // ttsCache.get call and goes straight to a hash-based lookup. Return cached audio there.
      const cachedAudio = Buffer.from('hash-cached');
      mockTtsCache.get.mockResolvedValue(cachedAudio);

      const result = await service.generate(DEVICE_ID, 'stand_up');

      expect(result.audio).toEqual(cachedAudio);
      expect(mockTts.synthesize).not.toHaveBeenCalled();
    });

    it('updates cache key on pool entry when newly generated', async () => {
      await service.generate(DEVICE_ID, 'stand_up');

      // updateCacheKey is called non-blocking
      await Promise.resolve();

      expect(mockResponsePool.updateCacheKey).toHaveBeenCalledWith('rp-1', CACHE_KEY);
    });

    it('does not call updateCacheKey when pool entry already has a cache key', async () => {
      mockResponsePool.pickLru.mockResolvedValue(makePoolEntry({ ttsCacheKey: 'existing-key' }));
      mockTtsCache.get.mockResolvedValue(Buffer.from('cached'));

      await service.generate(DEVICE_ID, 'stand_up');
      await Promise.resolve();

      expect(mockResponsePool.updateCacheKey).not.toHaveBeenCalled();
    });

    it('attaches correct display config for each reminder type', async () => {
      const types = ['stand_up', 'hydration', 'eye_break', 'stretch', 'posture'] as const;
      for (const type of types) {
        const result = await service.generate(DEVICE_ID, type);
        expect(result.display).toEqual(REMINDER_DISPLAY[type]);
      }
    });
  });

  // ── generatePomodoro (LLM fallback via pool) ─────────

  describe('generatePomodoro', () => {
    const focusState = {
      cycle: 1,
      phase: 'focus' as const,
      startedAt: new Date(),
      phaseStartedAt: new Date(),
      focusMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 15,
      cyclesBeforeLongBreak: 4,
      timer: null,
    };

    const breakState = {
      ...focusState,
      phase: 'short_break' as const,
    };

    it('picks from pomodoro_focus pool on focus phase', async () => {
      await service.generatePomodoro(DEVICE_ID, focusState);

      expect(mockResponsePool.pickLru).toHaveBeenCalledWith(DEVICE_ID, 'pomodoro_focus');
    });

    it('picks from pomodoro_break pool on break phase', async () => {
      await service.generatePomodoro(DEVICE_ID, breakState);

      expect(mockResponsePool.pickLru).toHaveBeenCalledWith(DEVICE_ID, 'pomodoro_break');
    });

    it('returns focused display for focus phase', async () => {
      const result = await service.generatePomodoro(DEVICE_ID, focusState);

      expect(result.display.expression).toBe('focused');
    });

    it('returns encouraging display for break phase', async () => {
      const result = await service.generatePomodoro(DEVICE_ID, breakState);

      expect(result.display.expression).toBe('encouraging');
    });

    it('returns correct type in payload for focus', async () => {
      const result = await service.generatePomodoro(DEVICE_ID, focusState);
      expect(result.type).toBe('pomodoro_focus');
    });

    it('returns correct type in payload for break', async () => {
      const result = await service.generatePomodoro(DEVICE_ID, breakState);
      expect(result.type).toBe('pomodoro_break');
    });

    it('synthesizes audio when cache misses', async () => {
      await service.generatePomodoro(DEVICE_ID, focusState);

      expect(mockTts.synthesize).toHaveBeenCalled();
      expect(mockCodec.encode).toHaveBeenCalled();
    });

    it('uses cached audio when pool entry has a cache key', async () => {
      const cachedAudio = Buffer.from('pomodoro-cached');
      mockResponsePool.pickLru.mockResolvedValue(makePoolEntry({ ttsCacheKey: 'pom-key' }));
      mockTtsCache.get.mockResolvedValue(cachedAudio);

      const result = await service.generatePomodoro(DEVICE_ID, focusState);

      expect(result.audio).toEqual(cachedAudio);
      expect(mockTts.synthesize).not.toHaveBeenCalled();
    });

    it('returns a payload with screenMode reminder', async () => {
      const result = await service.generatePomodoro(DEVICE_ID, focusState);
      expect(result.display.screenMode).toBe('reminder');
    });

    it('updates cache key non-blocking when newly synthesized', async () => {
      await service.generatePomodoro(DEVICE_ID, focusState);
      await Promise.resolve();

      expect(mockResponsePool.updateCacheKey).toHaveBeenCalledWith('rp-1', CACHE_KEY);
    });
  });

  // ── cacheAudio (getOrSynthesizeAudio internals) ──────

  describe('audio caching behaviour', () => {
    it('does not call TTS when both cache lookups succeed on first hit', async () => {
      mockResponsePool.pickLru.mockResolvedValue(makePoolEntry({ ttsCacheKey: 'key-hit' }));
      mockTtsCache.get.mockResolvedValue(Buffer.from('cached-audio'));

      await service.generate(DEVICE_ID, 'stand_up');

      expect(mockTts.synthesize).toHaveBeenCalledTimes(0);
    });

    it('calls TTS exactly once even across multiple cache misses', async () => {
      mockTtsCache.get.mockResolvedValue(null); // all cache misses

      await service.generate(DEVICE_ID, 'hydration');

      expect(mockTts.synthesize).toHaveBeenCalledTimes(1);
    });

    it('does not throw when ttsCache.set rejects', async () => {
      mockTtsCache.set.mockRejectedValue(new Error('Redis write error'));

      await expect(service.generate(DEVICE_ID, 'posture')).resolves.toBeDefined();
    });

    it('does not throw when updateCacheKey rejects', async () => {
      mockResponsePool.updateCacheKey.mockRejectedValue(new Error('DB write error'));

      await expect(service.generate(DEVICE_ID, 'stretch')).resolves.toBeDefined();
    });
  });
});
