import { SessionManager } from './session.manager';

describe('SessionManager', () => {
  let manager: SessionManager;

  beforeEach(() => {
    jest.useFakeTimers();
    manager = new SessionManager();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('create / get / remove', () => {
    it('creates and retrieves a session', () => {
      const session = manager.create('device-1', 'user-1');
      expect(session.deviceId).toBe('device-1');
      expect(session.userId).toBe('user-1');
      expect(session.state).toBe('idle');
      expect(session.conversationId).toBeNull();
      expect(session.interrupted).toBe(false);

      expect(manager.get('device-1')).toBe(session);
    });

    it('returns undefined for unknown device', () => {
      expect(manager.get('nonexistent')).toBeUndefined();
    });

    it('removes a session', () => {
      manager.create('device-1', 'user-1');
      manager.remove('device-1');
      expect(manager.get('device-1')).toBeUndefined();
    });

    it('remove is safe for unknown device', () => {
      expect(() => manager.remove('nonexistent')).not.toThrow();
    });
  });

  describe('setState / setConversation', () => {
    it('sets state', () => {
      manager.create('d1', 'u1');
      manager.setState('d1', 'listening');
      expect(manager.get('d1')!.state).toBe('listening');
    });

    it('sets conversation id', () => {
      manager.create('d1', 'u1');
      manager.setConversation('d1', 'conv-123');
      expect(manager.get('d1')!.conversationId).toBe('conv-123');
    });
  });

  describe('interruption', () => {
    it('marks and checks interrupted flag', () => {
      manager.create('d1', 'u1');
      expect(manager.isInterrupted('d1')).toBe(false);

      manager.markInterrupted('d1');
      expect(manager.isInterrupted('d1')).toBe(true);
    });

    it('clears interrupted flag', () => {
      manager.create('d1', 'u1');
      manager.markInterrupted('d1');
      manager.clearInterrupted('d1');
      expect(manager.isInterrupted('d1')).toBe(false);
    });

    it('returns false for unknown device', () => {
      expect(manager.isInterrupted('nonexistent')).toBe(false);
    });
  });

  describe('idle timer', () => {
    it('fires timeout callback after idle period', () => {
      manager.create('d1', 'u1');
      const onTimeout = jest.fn();

      manager.resetIdleTimer('d1', onTimeout);
      expect(onTimeout).not.toHaveBeenCalled();

      jest.advanceTimersByTime(5 * 60 * 1000);
      expect(onTimeout).toHaveBeenCalledTimes(1);
    });

    it('resets timer on subsequent calls', () => {
      manager.create('d1', 'u1');
      const onTimeout = jest.fn();

      manager.resetIdleTimer('d1', onTimeout);
      jest.advanceTimersByTime(4 * 60 * 1000); // 4 min

      // Reset — should restart the 5min countdown
      manager.resetIdleTimer('d1', onTimeout);
      jest.advanceTimersByTime(4 * 60 * 1000); // 4 more min
      expect(onTimeout).not.toHaveBeenCalled();

      jest.advanceTimersByTime(1 * 60 * 1000); // 5th min from reset
      expect(onTimeout).toHaveBeenCalledTimes(1);
    });

    it('clears timer on remove', () => {
      manager.create('d1', 'u1');
      const onTimeout = jest.fn();

      manager.resetIdleTimer('d1', onTimeout);
      manager.remove('d1');

      jest.advanceTimersByTime(10 * 60 * 1000);
      expect(onTimeout).not.toHaveBeenCalled();
    });
  });
});
