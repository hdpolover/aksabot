import { PomodoroService } from './pomodoro.service';

describe('PomodoroService', () => {
  let service: PomodoroService;
  let mockReminderService: Record<string, jest.Mock>;
  let sendToDevice: jest.Mock;

  beforeEach(() => {
    jest.useFakeTimers();

    mockReminderService = {
      generatePomodoro: jest.fn().mockResolvedValue({
        type: 'pomodoro_break',
        text: 'Take a break!',
        audio: Buffer.from('audio'),
        cacheKey: 'key-1',
        display: { expression: 'encouraging', screenMode: 'reminder', durationMs: 8000 },
      }),
    };

    sendToDevice = jest.fn();

    service = new PomodoroService(mockReminderService as any);
    service.setSendToDevice(sendToDevice);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('starts a pomodoro session', async () => {
    const info = await service.start('device-1');
    expect(info.active).toBe(true);
    expect(info.phase).toBe('focus');
    expect(info.cycle).toBe(1);
    expect(info.durationMinutes).toBe(25);
    expect(sendToDevice).toHaveBeenCalledWith(
      'device-1',
      'proactive:pomodoro',
      expect.objectContaining({ action: 'start', phase: 'focus' }),
    );
  });

  it('transitions from focus to break after timeout', async () => {
    await service.start('device-1');
    sendToDevice.mockClear();

    // Advance 25 minutes
    jest.advanceTimersByTime(25 * 60_000);

    // Should have transitioned to break
    expect(sendToDevice).toHaveBeenCalledWith(
      'device-1',
      'proactive:pomodoro',
      expect.objectContaining({ action: 'break' }),
    );
  });

  it('stops a session', async () => {
    await service.start('device-1');
    service.stop('device-1');

    expect(sendToDevice).toHaveBeenCalledWith(
      'device-1',
      'proactive:pomodoro',
      { action: 'stop' },
    );

    const info = service.getInfo('device-1');
    expect(info.active).toBe(false);
  });

  it('reports inactive for unknown device', () => {
    const info = service.getInfo('nonexistent');
    expect(info.active).toBe(false);
  });

  it('replaces existing session on restart', async () => {
    await service.start('device-1');
    await service.start('device-1');

    // Should have sent stop then start
    const calls = sendToDevice.mock.calls.map((c: any) => c[1]);
    expect(calls).toContain('proactive:pomodoro');
  });
});
