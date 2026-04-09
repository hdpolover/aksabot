import { PromptService } from './prompt.service';
import type { PersonalityConfig, MemoryEntry } from './prompt.service';

describe('PromptService', () => {
  let service: PromptService;

  beforeEach(() => {
    service = new PromptService();
  });

  describe('buildSystemPrompt', () => {
    it('uses default base prompt when no system_prompt is set', () => {
      const result = service.buildSystemPrompt({}, []);
      expect(result).toContain('helpful AI desk companion');
    });

    it('uses custom system_prompt when provided', () => {
      const personality: PersonalityConfig = {
        system_prompt: 'You are a pirate.',
      };
      const result = service.buildSystemPrompt(personality, []);
      expect(result).toContain('You are a pirate.');
      expect(result).not.toContain('helpful AI desk companion');
    });

    it('appends language hint when language is set', () => {
      const personality: PersonalityConfig = { language: 'Indonesian' };
      const result = service.buildSystemPrompt(personality, []);
      expect(result).toContain('Respond in Indonesian');
    });

    it('uses default language hint when no language is set', () => {
      const result = service.buildSystemPrompt({}, []);
      expect(result).toContain('Respond in the same language the user uses');
    });

    it('includes memory entries', () => {
      const memories: MemoryEntry[] = [
        { fact: 'User is a developer', category: 'profession' },
        { fact: 'User likes coffee', category: 'preference' },
      ];
      const result = service.buildSystemPrompt({}, memories);
      expect(result).toContain('User is a developer (profession)');
      expect(result).toContain('User likes coffee (preference)');
    });

    it('omits memory block when memories is empty', () => {
      const result = service.buildSystemPrompt({}, []);
      expect(result).not.toContain('You know the following');
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
