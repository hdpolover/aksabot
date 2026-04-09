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
      'You are a helpful AI desk companion. You are friendly, concise, and conversational. Keep responses short and natural for voice conversation.';

    const memoryBlock =
      memories.length > 0
        ? `\n\nYou know the following about the user:\n${memories.map((m) => `- ${m.fact} (${m.category})`).join('\n')}`
        : '';

    const languageHint = personality.language
      ? `\n\nRespond in ${personality.language}.`
      : '\n\nRespond in the same language the user uses.';

    return `${base}${memoryBlock}${languageHint}\nKeep responses concise and natural for voice conversation.`;
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
