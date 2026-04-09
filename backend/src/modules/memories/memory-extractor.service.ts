import { Inject, Injectable, Logger } from '@nestjs/common';
import { LLM_PROVIDER } from '../ai/interfaces/tokens';
import type { ILlmProvider } from '../ai/interfaces';

export interface ExtractedMemory {
  fact: string;
  category: string;
}

const VALID_CATEGORIES = [
  'personal',
  'preference',
  'work',
  'hobby',
  'relationship',
  'location',
  'routine',
  'other',
];

@Injectable()
export class MemoryExtractorService {
  private readonly logger = new Logger(MemoryExtractorService.name);

  constructor(
    @Inject(LLM_PROVIDER) private readonly llm: ILlmProvider,
  ) {}

  async extractFromTranscript(
    transcript: { role: string; content: string }[],
    existingMemories: { fact: string; category: string }[],
  ): Promise<ExtractedMemory[]> {
    if (transcript.length === 0) return [];

    const conversationText = transcript
      .map((m) => `${m.role}: ${m.content}`)
      .join('\n');

    const existingText =
      existingMemories.length > 0
        ? existingMemories.map((m) => `- ${m.fact} (${m.category})`).join('\n')
        : 'None';

    const systemPrompt = `You are a memory extraction system. You analyze conversations and extract facts about the user that are worth remembering for future conversations. Return ONLY valid JSON — no markdown, no code fences.`;

    const userMessage = `Given this conversation between a user and an AI assistant, extract any facts worth remembering about the user. Return a JSON array of objects with "fact" and "category" fields.

Categories: personal, preference, work, hobby, relationship, location, routine, other

Only extract facts that are:
- Explicitly stated by the user (not inferred or assumed)
- Likely to be useful in future conversations
- Not already known (check existing memories below)

If no new facts are found, return an empty array: []

Existing memories:
${existingText}

Conversation:
${conversationText}`;

    try {
      const response = await this.llm.generate(systemPrompt, [
        { role: 'user', content: userMessage },
      ]);

      return this.parseExtraction(response.text);
    } catch (err: any) {
      this.logger.error(`Memory extraction failed: ${err.message}`);
      return [];
    }
  }

  private parseExtraction(raw: string): ExtractedMemory[] {
    try {
      // Strip markdown code fences if present
      const cleaned = raw
        .replace(/```json\s*/gi, '')
        .replace(/```\s*/g, '')
        .trim();

      const parsed = JSON.parse(cleaned);

      if (!Array.isArray(parsed)) {
        this.logger.warn('Extraction response is not an array');
        return [];
      }

      return parsed
        .filter(
          (item: any) =>
            typeof item.fact === 'string' &&
            item.fact.trim().length > 0 &&
            typeof item.category === 'string' &&
            VALID_CATEGORIES.includes(item.category),
        )
        .map((item: any) => ({
          fact: item.fact.trim(),
          category: item.category,
        }));
    } catch (err: any) {
      this.logger.warn(`Failed to parse extraction response: ${err.message}`);
      this.logger.debug(`Raw response: ${raw.slice(0, 500)}`);
      return [];
    }
  }
}
