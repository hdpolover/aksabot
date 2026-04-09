import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Memory } from '../../core/database/entities';

/**
 * Phase 1 stub. Full implementation in Phase 3:
 * - Memory extraction from conversations via Gemini
 * - Confidence decay cron job
 * - Confidence boost on access
 */
@Injectable()
export class MemoriesService {
  constructor(
    @InjectRepository(Memory)
    private readonly memoriesRepo: Repository<Memory>,
  ) {}

  /** Get relevant memories for a device. Stub returns empty array. */
  async getRelevant(
    _deviceId: string,
    _limit = 20,
  ): Promise<{ fact: string; category: string }[]> {
    // TODO Phase 3: query by deviceId, order by confidence DESC, limit
    return [];
  }

  /** Bump lastAccessedAt for used memories. Stub is a no-op. */
  async bumpAccessed(_memoryIds: string[]): Promise<void> {
    // TODO Phase 3: update lastAccessedAt and boost confidence
  }

  /** List memories for a device (for Flutter app). */
  async findByDevice(deviceId: string, category?: string) {
    const where: any = { deviceId };
    if (category) where.category = category;

    return this.memoriesRepo.find({
      where,
      order: { confidence: 'DESC', lastAccessedAt: 'DESC' },
    });
  }

  /** Delete a memory. */
  async remove(id: string): Promise<void> {
    await this.memoriesRepo.delete(id);
  }
}
