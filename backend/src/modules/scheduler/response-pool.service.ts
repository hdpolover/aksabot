import { Inject, Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, Repository } from 'typeorm';
import { ResponsePool } from '../../core/database/entities';
import { LLM_PROVIDER } from '../ai/interfaces/tokens';
import type { ILlmProvider } from '../ai/interfaces';
import { POOL_TARGET_SIZES, POOL_GENERATION_PROMPTS } from './types';

@Injectable()
export class ResponsePoolService {
  private readonly logger = new Logger(ResponsePoolService.name);

  constructor(
    @InjectRepository(ResponsePool)
    private readonly repo: Repository<ResponsePool>,
    @Inject(LLM_PROVIDER) private readonly llm: ILlmProvider,
  ) {}

  /**
   * Pick the least recently used response for a category.
   * If pool is empty, generates one on the fly and stores it.
   */
  async pickLru(deviceId: string, category: string): Promise<ResponsePool> {
    // Prioritize never-used responses, then oldest-used
    let response = await this.repo.findOne({
      where: { deviceId, category, lastAccessedAt: IsNull() },
    });

    if (!response) {
      response = await this.repo.findOne({
        where: { deviceId, category },
        order: { lastAccessedAt: 'ASC' },
      });
    }

    if (response) {
      response.lastAccessedAt = new Date();
      response.useCount++;
      await this.repo.save(response);
      return response;
    }

    // Pool empty — generate a small batch (5) so the next few reminders
    // of this type don't each trigger a separate Gemini call
    const generated = await this.generateAndStore(deviceId, category, 5);
    if (generated.length === 0) {
      throw new Error(`Failed to generate pool entries for ${category}`);
    }
    return generated[0];
  }

  /**
   * Generate a batch of response variations and store them.
   */
  async generateAndStore(
    deviceId: string,
    category: string,
    count: number,
  ): Promise<ResponsePool[]> {
    const prompt = POOL_GENERATION_PROMPTS[category];
    if (!prompt) {
      this.logger.warn(`No generation prompt for category: ${category}`);
      return [];
    }

    try {
      const { text } = await this.llm.generate(
        `You are Aksa, an AI best friend with gen-z energy — sarcastic, funny, casually curses. ` +
          `Generate exactly ${count} variations, one per line. Each under 15 words. ` +
          `Vary the phrasing and energy — don't repeat the same opener. ` +
          `Never use text abbreviations (no fr, ngl, rn, lol) — spell them out, this is voice output. ` +
          `No numbering or bullet points.`,
        [{ role: 'user', content: prompt }],
      );

      const lines = text
        .split('\n')
        .map((l) => l.trim())
        .filter((l) => l.length > 0)
        .slice(0, count);

      const entries = lines.map((line) =>
        this.repo.create({ deviceId, category, text: line }),
      );

      const saved = await this.repo.save(entries);
      this.logger.log(
        `Generated ${saved.length} pool entries for ${category} (device ${deviceId})`,
      );
      return saved;
    } catch (err: any) {
      this.logger.error(`Pool generation failed: ${err.message}`);
      return [];
    }
  }

  /**
   * Check pool levels and refill categories that are running low.
   */
  async refillIfNeeded(deviceId: string): Promise<void> {
    for (const [category, targetSize] of Object.entries(POOL_TARGET_SIZES)) {
      const currentCount = await this.repo.count({
        where: { deviceId, category },
      });
      if (currentCount < targetSize) {
        const needed = targetSize - currentCount;
        await this.generateAndStore(deviceId, category, needed);
      }
    }
  }

  /**
   * Update TTS cache key for a pool entry.
   */
  async updateCacheKey(id: string, cacheKey: string): Promise<void> {
    await this.repo.update(id, { ttsCacheKey: cacheKey });
  }

  /**
   * Clear all pool entries for a device (e.g., after personality change).
   */
  async clearForDevice(deviceId: string): Promise<void> {
    await this.repo.delete({ deviceId });
    this.logger.log(`Cleared response pool for device ${deviceId}`);
  }

  /**
   * Get pool stats for a device (for status display).
   */
  async getStats(
    deviceId: string,
  ): Promise<{ category: string; count: number }[]> {
    const result = await this.repo
      .createQueryBuilder('rp')
      .select('rp.category', 'category')
      .addSelect('COUNT(*)', 'count')
      .where('rp.device_id = :deviceId', { deviceId })
      .groupBy('rp.category')
      .getRawMany();

    return result.map((r) => ({
      category: r.category,
      count: parseInt(r.count, 10),
    }));
  }
}
