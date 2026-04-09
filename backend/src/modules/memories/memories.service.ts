import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { MoreThan, Repository } from 'typeorm';
import { Memory, Message } from '../../core/database/entities';
import { MemoryExtractorService } from './memory-extractor.service';

@Injectable()
export class MemoriesService {
  private readonly logger = new Logger(MemoriesService.name);

  constructor(
    @InjectRepository(Memory)
    private readonly memoriesRepo: Repository<Memory>,
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
    private readonly extractor: MemoryExtractorService,
  ) {}

  // ── Retrieval ─────────────────────────────────────────

  async getRelevant(
    deviceId: string,
    limit = 20,
  ): Promise<{ id: string; fact: string; category: string }[]> {
    const memories = await this.memoriesRepo.find({
      where: { deviceId, confidence: MoreThan(0.1) },
      order: { confidence: 'DESC', lastAccessedAt: 'DESC' },
      take: limit,
    });

    return memories.map((m) => ({
      id: m.id,
      fact: m.fact,
      category: m.category,
    }));
  }

  // ── Confidence boost ──────────────────────────────────

  async bumpAccessed(memoryIds: string[]): Promise<void> {
    if (memoryIds.length === 0) return;

    await this.memoriesRepo
      .createQueryBuilder()
      .update(Memory)
      .set({
        lastAccessedAt: () => 'now()',
        confidence: () => 'LEAST(1.0, confidence + 0.1)',
      })
      .whereInIds(memoryIds)
      .execute();
  }

  // ── Extraction ────────────────────────────────────────

  async extractFromConversation(
    conversationId: string,
    deviceId: string,
  ): Promise<Memory[]> {
    // Get conversation messages
    const messages = await this.messagesRepo.find({
      where: { conversationId },
      order: { createdAt: 'ASC' },
    });

    if (messages.length === 0) return [];

    const transcript = messages.map((m) => ({
      role: m.role,
      content: m.content,
    }));

    // Get existing memories to avoid duplicates
    const existing = await this.memoriesRepo.find({
      where: { deviceId },
      select: ['fact', 'category'],
    });

    // Extract new facts
    const extracted = await this.extractor.extractFromTranscript(
      transcript,
      existing,
    );

    if (extracted.length === 0) return [];

    // Find the last user message to link as source
    const lastUserMessage = messages
      .filter((m) => m.role === 'user')
      .pop();

    // Save new memories
    const newMemories = extracted.map((e) =>
      this.memoriesRepo.create({
        deviceId,
        fact: e.fact,
        category: e.category,
        confidence: 1.0,
        sourceMessageId: lastUserMessage?.id ?? undefined,
      }),
    );

    const saved = await this.memoriesRepo.save(newMemories);
    this.logger.log(
      `Extracted ${saved.length} memories from conversation ${conversationId}`,
    );
    return saved;
  }

  // ── Decay ─────────────────────────────────────────────

  async applyDecay(): Promise<{ decayed: number; deleted: number }> {
    // Apply tiered decay based on time since last access
    const decayResult = await this.memoriesRepo
      .createQueryBuilder()
      .update(Memory)
      .set({
        confidence: () => `confidence * CASE
          WHEN last_accessed_at > now() - interval '7 days' THEN 1.0
          WHEN last_accessed_at > now() - interval '30 days' THEN 0.99
          WHEN last_accessed_at > now() - interval '90 days' THEN 0.97
          ELSE 0.95
        END`,
      })
      .where('confidence > 0.1')
      .execute();

    // Delete memories below threshold
    const deleteResult = await this.memoriesRepo
      .createQueryBuilder()
      .delete()
      .from(Memory)
      .where('confidence <= 0.1')
      .execute();

    const decayed = decayResult.affected ?? 0;
    const deleted = deleteResult.affected ?? 0;

    this.logger.log(`Decay complete: ${decayed} updated, ${deleted} deleted`);
    return { decayed, deleted };
  }

  // ── CRUD (for Flutter app) ────────────────────────────

  async findByDevice(deviceId: string, category?: string) {
    const where: any = { deviceId };
    if (category) where.category = category;

    return this.memoriesRepo.find({
      where,
      order: { confidence: 'DESC', lastAccessedAt: 'DESC' },
    });
  }

  async update(
    id: string,
    updates: { fact?: string; category?: string },
  ): Promise<Memory> {
    const memory = await this.memoriesRepo.findOne({ where: { id } });
    if (!memory) throw new NotFoundException('Memory not found');

    if (updates.fact !== undefined) memory.fact = updates.fact;
    if (updates.category !== undefined) memory.category = updates.category;

    return this.memoriesRepo.save(memory);
  }

  async remove(id: string): Promise<void> {
    const result = await this.memoriesRepo.delete(id);
    if (result.affected === 0) {
      throw new NotFoundException('Memory not found');
    }
  }
}
