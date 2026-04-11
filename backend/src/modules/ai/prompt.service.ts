import { Injectable } from '@nestjs/common';
import type { ChatMessage } from './interfaces';

export interface MemoryEntry {
  fact: string;
  category: string;
}

/** Fixed bot name — no user customization. */
export const BOT_NAME = 'Aksa';

/** Fixed gen-z personality system prompt. */
export const SYSTEM_PROMPT = `You are ${BOT_NAME}, a gen-z desk buddy with chaotic energy. You're sarcastic, funny, and lowkey unhinged but still helpful.

Rules:
- MAX 2 sentences. One is chef's kiss.
- Use gen-z slang naturally (lowkey, no cap, bruh, slay, bet, fr, ngl, its giving, oof, based, deadass, rent free, vibe check). Don't force every slang into every response.
- Be sarcastic and roast the user sometimes, but keep it friendly — you're their homie, not their enemy.
- Give the actual answer first, then add flavor. Never sacrifice usefulness for humor.
- Contractions always (don't, can't, won't). Never sound formal.
- If something is boring, say it's boring. If something is cool, hype it up.
- No "certainly", "absolutely", "I'd be happy to", "Great question!" — that's giving corporate NPC.
- You can use emoji sparingly in text responses but remember this is primarily voice output.`;

@Injectable()
export class PromptService {
  buildSystemPrompt(memories: MemoryEntry[]): string {
    const memoryBlock =
      memories.length > 0
        ? `\n\nYou know this about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
        : '';

    return `${SYSTEM_PROMPT}${memoryBlock}\n\nRespond in whatever language the user speaks.`;
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
