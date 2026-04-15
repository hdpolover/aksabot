import { Inject, Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Between, Repository } from 'typeorm';
import { Conversation, Message, MoodEntry } from '../../core/database/entities';
import { LLM_PROVIDER } from '../ai/interfaces/tokens';
import type { ILlmProvider } from '../ai/interfaces';

const VALID_MOODS = [
  'happy',
  'tired',
  'stressed',
  'chill',
  'frustrated',
  'excited',
  'sad',
  'neutral',
];

@Injectable()
export class MoodJournalService {
  private readonly logger = new Logger(MoodJournalService.name);

  constructor(
    @InjectRepository(MoodEntry)
    private readonly moodRepo: Repository<MoodEntry>,
    @InjectRepository(Conversation)
    private readonly conversationsRepo: Repository<Conversation>,
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
    @Inject(LLM_PROVIDER) private readonly llm: ILlmProvider,
  ) {}

  /**
   * Analyze today's conversations for a device and extract an overall mood.
   * Stores one entry per device per day (upserts on conflict).
   */
  async extractDailyMood(
    deviceId: string,
    timezone?: string,
  ): Promise<MoodEntry | null> {
    const tz = timezone || process.env.TZ || 'Asia/Jakarta';
    const today = new Date().toLocaleDateString('en-CA', { timeZone: tz }); // YYYY-MM-DD

    // Check if we already have an entry for today
    const existing = await this.moodRepo.findOne({
      where: { deviceId, date: today },
    });
    if (existing) {
      this.logger.debug(`Mood already recorded for ${deviceId} on ${today}`);
      return existing;
    }

    // Get today's conversations
    const dayStart = new Date(`${today}T00:00:00`);
    const dayEnd = new Date(`${today}T23:59:59`);

    const conversations = await this.conversationsRepo.find({
      where: {
        deviceId,
        startedAt: Between(dayStart, dayEnd),
      },
    });

    if (conversations.length === 0) {
      this.logger.debug(
        `No conversations for ${deviceId} on ${today} — skipping mood extraction`,
      );
      return null;
    }

    // Get all messages from today's conversations
    const allMessages: { role: string; content: string }[] = [];
    for (const conv of conversations) {
      const messages = await this.messagesRepo.find({
        where: { conversationId: conv.id },
        order: { createdAt: 'ASC' },
      });
      allMessages.push(
        ...messages.map((m) => ({
          role: m.role,
          content: m.content,
        })),
      );
    }

    if (allMessages.length < 2) {
      this.logger.debug(
        `Too few messages for ${deviceId} on ${today} — skipping mood extraction`,
      );
      return null;
    }

    // Extract mood via LLM
    const transcript = allMessages
      .map((m) => `${m.role}: ${m.content}`)
      .join('\n');

    try {
      const { text } = await this.llm.generate(
        "You are a mood analysis system. Analyze conversations and determine the user's overall mood for the day. Return ONLY valid JSON — no markdown, no code fences.",
        [
          {
            role: 'user',
            content: `Analyze the user's overall mood from today's conversations. Return a JSON object with:
- "mood": one of [${VALID_MOODS.join(', ')}]
- "note": a brief 1-sentence explanation of why (max 20 words)

Only consider what the USER said, not the assistant.

Conversations:
${transcript}`,
          },
        ],
      );

      const parsed = this.parseMoodResponse(text);
      if (!parsed) return null;

      const entry = this.moodRepo.create({
        deviceId,
        date: today,
        mood: parsed.mood,
        note: parsed.note,
      });

      const saved = await this.moodRepo.save(entry);
      this.logger.log(
        `Mood for ${deviceId} on ${today}: ${saved.mood} — ${saved.note}`,
      );
      return saved;
    } catch (err: any) {
      this.logger.warn(
        `Mood extraction failed for ${deviceId}: ${err.message}`,
      );
      return null;
    }
  }

  private parseMoodResponse(
    raw: string,
  ): { mood: string; note: string } | null {
    try {
      let cleaned = raw
        .replace(/```json\s*/gi, '')
        .replace(/```\s*/g, '')
        .trim();

      // Extract JSON object
      const objStart = cleaned.indexOf('{');
      const objEnd = cleaned.lastIndexOf('}');
      if (objStart !== -1 && objEnd > objStart) {
        cleaned = cleaned.slice(objStart, objEnd + 1);
      }

      const parsed = JSON.parse(cleaned);
      if (!parsed.mood || !VALID_MOODS.includes(parsed.mood)) {
        this.logger.warn(`Invalid mood value: ${parsed.mood}`);
        return null;
      }

      return {
        mood: parsed.mood,
        note: typeof parsed.note === 'string' ? parsed.note.trim() : '',
      };
    } catch (err: any) {
      this.logger.warn(
        `Failed to parse mood response: ${err.message} | Raw: ${raw.slice(0, 200)}`,
      );
      return null;
    }
  }

  /**
   * Get recent mood entries for a device (for system prompt context).
   */
  async getRecentMoods(deviceId: string, days = 7): Promise<MoodEntry[]> {
    const since = new Date();
    since.setDate(since.getDate() - days);
    const sinceStr = since.toISOString().slice(0, 10);

    return this.moodRepo.find({
      where: {
        deviceId,
        date: Between(sinceStr, new Date().toISOString().slice(0, 10)) as any,
      },
      order: { date: 'DESC' },
    });
  }

  /**
   * Get all mood entries for a device (for Flutter app).
   */
  async findByDevice(deviceId: string, limit = 30): Promise<MoodEntry[]> {
    return this.moodRepo.find({
      where: { deviceId },
      order: { date: 'DESC' },
      take: limit,
    });
  }
}
