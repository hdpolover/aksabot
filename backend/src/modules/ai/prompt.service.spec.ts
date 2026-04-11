import { PromptService, BOT_NAME, SYSTEM_PROMPT } from './prompt.service';
import type { MemoryEntry } from './prompt.service';

describe('PromptService', () => {
  let service: PromptService;

  beforeEach(() => {
    service = new PromptService();
  });

  describe('buildSystemPrompt', () => {
    it('uses fixed gen-z personality prompt with bot name', () => {
      const result = service.buildSystemPrompt([]);
      expect(result).toContain(BOT_NAME);
      expect(result).toContain('gen-z desk buddy');
    });

    it('includes auto-detect language hint', () => {
      const result = service.buildSystemPrompt([]);
      expect(result).toContain('Respond in whatever language the user speaks');
    });

    it('includes memory entries', () => {
      const memories: MemoryEntry[] = [
        { fact: 'User is a developer', category: 'profession' },
        { fact: 'User likes coffee', category: 'preference' },
      ];
      const result = service.buildSystemPrompt(memories);
      expect(result).toContain('User is a developer');
      expect(result).toContain('User likes coffee');
    });

    it('omits memory block when memories is empty', () => {
      const result = service.buildSystemPrompt([]);
      expect(result).not.toContain('You know this about the user');
    });
  });

  describe('buildMessages', () => {
    it('appends user message to history', () => {
      const history = [
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there' },
      ];
      const result = service.buildMessages(history, 'How are you?');
      expect(result).toHaveLength(3);
      expect(result[2]).toEqual({ role: 'user', content: 'How are you?' });
    });

    it('works with empty history', () => {
      const result = service.buildMessages([], 'First message');
      expect(result).toEqual([{ role: 'user', content: 'First message' }]);
    });

    it('preserves role types from history', () => {
      const history = [
        { role: 'user', content: 'A' },
        { role: 'assistant', content: 'B' },
      ];
      const result = service.buildMessages(history, 'C');
      expect(result[0].role).toBe('user');
      expect(result[1].role).toBe('assistant');
    });
  });
});
