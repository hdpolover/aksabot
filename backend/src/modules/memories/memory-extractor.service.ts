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

  constructor(@Inject(LLM_PROVIDER) private readonly llm: ILlmProvider) {}

  async extractFromTranscript(
    transcript: { role: string; content: string }[],
    existingMemories: { fact: string; category: string }[],
  ): Promise<ExtractedMemory[]> {
    if (transcript.length === 0) {
      this.logger.debug('Skipping extraction: empty transcript');
      return [];
    }

    const conversationText = transcript
      .map((m) => `${m.role}: ${m.content}`)
      .join('\n');

    const existingText =
      existingMemories.length > 0
        ? existingMemories.map((m) => `- ${m.fact} (${m.category})`).join('\n')
        : 'None';

    const systemPrompt = `You are a memory extraction system. You analyze conversations and extract facts about the user that are worth remembering for future conversations. Return ONLY a valid JSON array — no markdown, no code fences, no explanation text.`;

    const userMessage = `Given this conversation between a user and an AI assistant, extract any facts worth remembering about the user. Return a JSON array of objects with "fact" and "category" fields.

Categories: personal, preference, work, hobby, relationship, location, routine, other

Only extract facts that are:
- Explicitly stated by the user (not inferred or assumed)
- Likely to be useful in future conversations
- Not already known (check existing memories below)

If no new facts are found, return an empty array: []

Example response format:
[{"fact": "User is a software developer", "category": "work"}, {"fact": "User likes coffee", "category": "preference"}]

Existing memories:
${existingText}

Conversation:
${conversationText}`;

    try {
      const response = await this.llm.generate(systemPrompt, [
        { role: 'user', content: userMessage },
      ]);

      if (!response.text || response.text.trim() === '') {
        this.logger.warn(
          `LLM returned empty response for extraction (${transcript.length} messages). ` +
            `Likely blocked by safety filter or no content generated.`,
        );
        return [];
      }

      this.logger.debug(
        `Extraction LLM response (${response.text.length} chars): ${response.text.slice(0, 300)}`,
      );

      return this.parseExtraction(response.text);
    } catch (err: any) {
      this.logger.error(`Memory extraction LLM call failed: ${err.message}`);
      return [];
    }
  }

  private parseExtraction(raw: string): ExtractedMemory[] {
    try {
      // Strip markdown code fences if present
      let cleaned = raw
        .replace(/```json\s*/gi, '')
        .replace(/```\s*/g, '')
        .trim();

      // If the response has preamble text before the JSON array, extract just the array
      const arrayStart = cleaned.indexOf('[');
      const arrayEnd = cleaned.lastIndexOf(']');
      if (arrayStart !== -1 && arrayEnd !== -1 && arrayEnd > arrayStart) {
        cleaned = cleaned.slice(arrayStart, arrayEnd + 1);
      }

      if (cleaned === '' || cleaned === '[]') {
        this.logger.debug('Extraction returned empty array');
        return [];
      }

      const parsed = JSON.parse(cleaned);

      if (!Array.isArray(parsed)) {
        this.logger.warn(
          `Extraction response is not an array (type=${typeof parsed}): ${raw.slice(0, 200)}`,
        );
        return [];
      }

      const valid = parsed
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

      const filtered = parsed.length - valid.length;
      if (filtered > 0) {
        this.logger.debug(
          `Filtered ${filtered}/${parsed.length} items (invalid category or empty fact)`,
        );
      }

      return valid;
    } catch (err: any) {
      this.logger.warn(
        `Failed to parse extraction response: ${err.message} | ` +
          `Raw (${raw.length} chars): ${raw.slice(0, 300)}`,
      );
      return [];
    }
  }
}
