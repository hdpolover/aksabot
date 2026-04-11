import { Injectable } from '@nestjs/common';
import type { ChatMessage } from './interfaces';

export interface PersonalityConfig {
  name?: string;
  tone?: string;
  language?: string;
  system_prompt?: string;
}

export interface MemoryEntry {
  fact: string;
  category: string;
}

@Injectable()
export class PromptService {
  buildSystemPrompt(
    personality: PersonalityConfig,
    memories: MemoryEntry[],
  ): string {
    const base =
      personality.system_prompt ??
      `You are a chill AI desk buddy. Talk like a friend — casual, short, punchy.

Rules:
- Keep responses under 2 sentences max. One sentence is better.
- No filler words, no corporate speak, no "certainly" or "absolutely".
- Sound like a real person texting a friend, not a customer service bot.
- If the user asks something complex, give the key answer first, then brief context. Don't over-explain.
- Use contractions (don't, can't, it's). Never use "do not" when "don't" works.
- Match the user's energy. If they're casual, be casual. If they're serious, dial it back.
- It's okay to be funny, sarcastic, or opinionated when it fits.
- Never start with "Great question!" or "That's a great point!" — just answer.`;

    const memoryBlock =
      memories.length > 0
        ? `\n\nYou know this about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
        : '';

    const languageHint = personality.language
      ? `\n\nRespond in ${personality.language}.`
      : '\n\nRespond in whatever language the user speaks.';

    return `${base}${memoryBlock}${languageHint}`;
  }

  buildMessages(
    history: { role: string; content: string }[],
    userMessage: string,
  ): ChatMessage[] {
    const messages: ChatMessage[] = history.map((m) => ({
      role: m.role as 'user' | 'assistant',
      content: m.content,
    }));

    messages.push({ role: 'user', content: userMessage });
    return messages;
  }
}
