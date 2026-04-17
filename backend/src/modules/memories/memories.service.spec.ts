import { NotFoundException } from '@nestjs/common';
import { MemoriesService } from './memories.service';

describe('MemoriesService', () => {
  let service: MemoriesService;
  let memoriesRepo: Record<string, jest.Mock>;
  let messagesRepo: Record<string, jest.Mock>;
  let extractor: Record<string, jest.Mock>;

  const mockMemory = {
    id: 'mem-1',
    deviceId: 'device-1',
    fact: 'User is a developer',
    category: 'work',
    confidence: 0.9,
    lastAccessedAt: new Date(),
  };

  beforeEach(() => {
    memoriesRepo = {
      find: jest.fn().mockResolvedValue([mockMemory]),
      findOne: jest.fn(),
      create: jest
        .fn()
        .mockImplementation((data) => ({ ...mockMemory, ...data })),
      save: jest
        .fn()
        .mockImplementation((data) =>
          Array.isArray(data) ? Promise.resolve(data) : Promise.resolve(data),
        ),
      delete: jest.fn().mockResolvedValue({ affected: 1 }),
      createQueryBuilder: jest.fn().mockReturnValue({
        update: jest.fn().mockReturnThis(),
        set: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        whereInIds: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        from: jest.fn().mockReturnThis(),
        execute: jest.fn().mockResolvedValue({ affected: 5 }),
      }),
    };

    messagesRepo = {
      find: jest.fn().mockResolvedValue([]),
    };

    extractor = {
      extractFromTranscript: jest.fn().mockResolvedValue([]),
    };

    const conversationsRepo = {
      find: jest.fn().mockResolvedValue([]),
      findOne: jest.fn().mockResolvedValue(null),
    };
    service = new MemoriesService(
      memoriesRepo as any,
      messagesRepo as any,
      conversationsRepo as any,
      extractor as any,
    );
  });

  describe('getRelevant', () => {
    it('returns memories ordered by confidence', async () => {
      const result = await service.getRelevant('device-1');
      expect(result).toEqual([
        { id: 'mem-1', fact: 'User is a developer', category: 'work' },
      ]);
      expect(memoriesRepo.find).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ deviceId: 'device-1' }),
          order: { confidence: 'DESC', lastAccessedAt: 'DESC' },
          take: 20,
        }),
      );
    });

    it('respects custom limit', async () => {
      await service.getRelevant('device-1', 5);
      expect(memoriesRepo.find).toHaveBeenCalledWith(
        expect.objectContaining({ take: 5 }),
      );
    });
  });

  describe('getStratifiedSample', () => {
    it('returns all memories when pool is smaller than limit', async () => {
      memoriesRepo.find.mockResolvedValue([mockMemory]);
      const result = await service.getStratifiedSample('device-1', 8);
      expect(result).toEqual([
        { id: 'mem-1', fact: 'User is a developer', category: 'work' },
      ]);
    });

    it('mixes fresh, anchor, and wildcard strata when pool is large', async () => {
      const now = Date.now();
      const recent = new Date(now - 24 * 60 * 60_000); // yesterday
      const old = new Date(now - 60 * 24 * 60 * 60_000); // 60 days ago
      const pool = [
        // High-confidence anchors (old, so not fresh)
        { id: 'a1', fact: 'anchor 1', category: 'c', confidence: 1.0, lastAccessedAt: old },
        { id: 'a2', fact: 'anchor 2', category: 'c', confidence: 0.95, lastAccessedAt: old },
        // Fresh (recent, mid-confidence)
        { id: 'f1', fact: 'fresh 1', category: 'c', confidence: 0.5, lastAccessedAt: recent },
        { id: 'f2', fact: 'fresh 2', category: 'c', confidence: 0.5, lastAccessedAt: recent },
        // Wildcards (old, mid-confidence)
        { id: 'w1', fact: 'wild 1', category: 'c', confidence: 0.5, lastAccessedAt: old },
        { id: 'w2', fact: 'wild 2', category: 'c', confidence: 0.5, lastAccessedAt: old },
        { id: 'w3', fact: 'wild 3', category: 'c', confidence: 0.5, lastAccessedAt: old },
        { id: 'w4', fact: 'wild 4', category: 'c', confidence: 0.5, lastAccessedAt: old },
        { id: 'w5', fact: 'wild 5', category: 'c', confidence: 0.5, lastAccessedAt: old },
      ];
      memoriesRepo.find.mockResolvedValue(pool);

      const result = await service.getStratifiedSample('device-1', 6);
      expect(result).toHaveLength(6);
      const ids = result.map((r) => r.id);
      expect(new Set(ids).size).toBe(6); // no duplicates
    });

    it('filters out low-confidence memories via query', async () => {
      await service.getStratifiedSample('device-1');
      expect(memoriesRepo.find).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ deviceId: 'device-1' }),
        }),
      );
    });
  });

  describe('getRecentExchanges', () => {
    it('returns empty when no conversations exist', async () => {
      const result = await service.getRecentExchanges('device-1');
      expect(result).toEqual([]);
    });

    it('returns recent messages in chronological order', async () => {
      const conversationsRepo = (service as any).conversationsRepo;
      conversationsRepo.findOne.mockResolvedValue({ id: 'conv-1' });

      const now = new Date();
      messagesRepo.find.mockResolvedValue([
        { role: 'assistant', content: 'B', createdAt: new Date(now.getTime() - 1000) },
        { role: 'user', content: 'A', createdAt: new Date(now.getTime() - 2000) },
      ]);

      const result = await service.getRecentExchanges('device-1', 2);
      expect(result).toEqual([
        { role: 'user', content: 'A' },
        { role: 'assistant', content: 'B' },
      ]);
    });
  });

  describe('bumpAccessed', () => {
    it('does nothing for empty array', async () => {
      await service.bumpAccessed([]);
      expect(memoriesRepo.createQueryBuilder).not.toHaveBeenCalled();
    });

    it('updates confidence and lastAccessedAt', async () => {
      await service.bumpAccessed(['mem-1', 'mem-2']);
      const qb = memoriesRepo.createQueryBuilder();
      expect(qb.update).toHaveBeenCalled();
      expect(qb.whereInIds).toHaveBeenCalledWith(['mem-1', 'mem-2']);
    });
  });

  describe('extractFromConversation', () => {
    it('returns empty for conversation with no messages', async () => {
      const result = await service.extractFromConversation(
        'conv-1',
        'device-1',
      );
      expect(result).toEqual([]);
    });

    it('bails early on guest-tagged conversations without calling the extractor', async () => {
      const conversationsRepo = (service as any).conversationsRepo;
      conversationsRepo.findOne.mockResolvedValue({
        id: 'conv-1',
        guestMode: true,
      });
      // Even if messages exist, guest-tagged conversations must not extract.
      messagesRepo.find.mockResolvedValue([
        {
          id: 'msg-1',
          role: 'user',
          content: 'Hi my name is Ryan',
          createdAt: new Date(),
        },
      ]);

      const result = await service.extractFromConversation(
        'conv-1',
        'device-1',
      );

      expect(result).toEqual([]);
      expect(extractor.extractFromTranscript).not.toHaveBeenCalled();
      expect(memoriesRepo.save).not.toHaveBeenCalled();
    });

    it('still extracts when the conversation is not guest-tagged', async () => {
      const conversationsRepo = (service as any).conversationsRepo;
      conversationsRepo.findOne.mockResolvedValue({
        id: 'conv-1',
        guestMode: false,
      });
      messagesRepo.find.mockResolvedValue([
        {
          id: 'msg-1',
          role: 'user',
          content: 'I love coffee',
          createdAt: new Date(),
        },
      ]);
      memoriesRepo.find.mockResolvedValue([]);
      extractor.extractFromTranscript.mockResolvedValue([
        { fact: 'User loves coffee', category: 'preference' },
      ]);

      await service.extractFromConversation('conv-1', 'device-1');
      expect(extractor.extractFromTranscript).toHaveBeenCalled();
    });

    it('extracts and saves memories', async () => {
      messagesRepo.find.mockResolvedValue([
        {
          id: 'msg-1',
          role: 'user',
          content: 'I am a developer',
          createdAt: new Date(),
        },
        {
          id: 'msg-2',
          role: 'assistant',
          content: 'Cool!',
          createdAt: new Date(),
        },
      ]);
      memoriesRepo.find.mockResolvedValue([]); // no existing memories
      extractor.extractFromTranscript.mockResolvedValue([
        { fact: 'User is a developer', category: 'work' },
      ]);

      await service.extractFromConversation('conv-1', 'device-1');

      expect(extractor.extractFromTranscript).toHaveBeenCalled();
      expect(memoriesRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({
          deviceId: 'device-1',
          fact: 'User is a developer',
          category: 'work',
          confidence: 1.0,
          sourceMessageId: 'msg-1',
        }),
      );
      expect(memoriesRepo.save).toHaveBeenCalled();
    });
  });

  describe('applyDecay', () => {
    it('runs decay and delete queries', async () => {
      const result = await service.applyDecay();
      expect(result).toEqual({ decayed: 5, deleted: 5 });
    });
  });

  describe('update', () => {
    it('updates fact and category', async () => {
      memoriesRepo.findOne.mockResolvedValue({ ...mockMemory });
      const result = await service.update('mem-1', {
        fact: 'Updated fact',
        category: 'personal',
      });
      expect(result.fact).toBe('Updated fact');
      expect(result.category).toBe('personal');
    });

    it('throws NotFoundException for missing memory', async () => {
      memoriesRepo.findOne.mockResolvedValue(null);
      await expect(service.update('bad-id', { fact: 'x' })).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('remove', () => {
    it('deletes a memory', async () => {
      await service.remove('mem-1');
      expect(memoriesRepo.delete).toHaveBeenCalledWith('mem-1');
    });

    it('throws NotFoundException if not found', async () => {
      memoriesRepo.delete.mockResolvedValue({ affected: 0 });
      await expect(service.remove('bad-id')).rejects.toThrow(NotFoundException);
    });
  });
});
