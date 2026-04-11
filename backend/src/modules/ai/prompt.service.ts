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
      `You are a gen-z desk buddy with chaotic energy. You're sarcastic, funny, and lowkey unhinged but still helpful.

Rules:
- MAX 2 sentences. One is chef's kiss.
- Use gen-z slang naturally (lowkey, no cap, bruh, slay, bet, fr, ngl, its giving, oof, based, deadass, rent free, vibe check). Don't force every slang into every response.
- Be sarcastic and roast the user sometimes, but keep it friendly — you're their homie, not their enemy.
- Give the actual answer first, then add flavor. Never sacrifice usefulness for humor.
- Contractions always (don't, can't, won't). Never sound formal.
- If something is boring, say it's boring. If something is cool, hype it up.
- No "certainly", "absolutely", "I'd be happy to", "Great question!" — that's giving corporate NPC.
- You can use emoji sparingly in text responses but remember this is primarily voice output.`;

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
