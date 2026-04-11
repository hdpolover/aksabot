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
      create: jest.fn().mockImplementation((data) => ({ ...mockMemory, ...data })),
      save: jest.fn().mockImplementation((data) =>
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

    const conversationsRepo = { find: jest.fn().mockResolvedValue([]) };
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
      const result = await service.extractFromConversation('conv-1', 'device-1');
      expect(result).toEqual([]);
    });

    it('extracts and saves memories', async () => {
      messagesRepo.find.mockResolvedValue([
        { id: 'msg-1', role: 'user', content: 'I am a developer', createdAt: new Date() },
        { id: 'msg-2', role: 'assistant', content: 'Cool!', createdAt: new Date() },
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
      await expect(service.remove('bad-id')).rejects.toThrow(
        NotFoundException,
      );
    });
  });
});
