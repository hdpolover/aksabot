import { NotFoundException } from '@nestjs/common';
import { MemoriesController } from './memories.controller';

describe('MemoriesController', () => {
  let controller: MemoriesController;
  let memoriesService: Record<string, jest.Mock>;

  const mockMemory = {
    id: 'mem-1',
    deviceId: 'device-1',
    fact: 'User is a developer',
    category: 'work',
    confidence: 0.9,
    lastAccessedAt: new Date(),
    createdAt: new Date(),
  };

  beforeEach(() => {
    memoriesService = {
      findByDevice: jest.fn(),
      update: jest.fn(),
      remove: jest.fn(),
    };

    controller = new MemoriesController(memoriesService as any);
  });

  describe('findByDevice', () => {
    it('returns all memories for a device', async () => {
      memoriesService.findByDevice.mockResolvedValue([mockMemory]);

      const result = await controller.findByDevice('device-1');

      expect(memoriesService.findByDevice).toHaveBeenCalledWith('device-1', undefined);
      expect(result).toEqual([mockMemory]);
    });

    it('filters memories by category when provided', async () => {
      const workMemory = { ...mockMemory, category: 'work' };
      memoriesService.findByDevice.mockResolvedValue([workMemory]);

      const result = await controller.findByDevice('device-1', 'work');

      expect(memoriesService.findByDevice).toHaveBeenCalledWith('device-1', 'work');
      expect(result).toEqual([workMemory]);
    });

    it('returns empty array when device has no memories', async () => {
      memoriesService.findByDevice.mockResolvedValue([]);

      const result = await controller.findByDevice('device-1');
      expect(result).toEqual([]);
    });

    it('returns memories across multiple categories when no filter is given', async () => {
      const memories = [
        { ...mockMemory, category: 'work' },
        { ...mockMemory, id: 'mem-2', category: 'personal' },
      ];
      memoriesService.findByDevice.mockResolvedValue(memories);

      const result = await controller.findByDevice('device-1', undefined);
      expect(result).toHaveLength(2);
    });
  });

  describe('update', () => {
    it('updates fact and returns the updated memory', async () => {
      const updated = { ...mockMemory, fact: 'User is a senior developer' };
      memoriesService.update.mockResolvedValue(updated);

      const result = await controller.update('mem-1', { fact: 'User is a senior developer' });

      expect(memoriesService.update).toHaveBeenCalledWith('mem-1', {
        fact: 'User is a senior developer',
      });
      expect(result.fact).toBe('User is a senior developer');
    });

    it('updates category and returns the updated memory', async () => {
      const updated = { ...mockMemory, category: 'personal' };
      memoriesService.update.mockResolvedValue(updated);

      const result = await controller.update('mem-1', { category: 'personal' });

      expect(memoriesService.update).toHaveBeenCalledWith('mem-1', { category: 'personal' });
      expect(result.category).toBe('personal');
    });

    it('updates both fact and category together', async () => {
      const updated = { ...mockMemory, fact: 'New fact', category: 'personal' };
      memoriesService.update.mockResolvedValue(updated);

      const result = await controller.update('mem-1', {
        fact: 'New fact',
        category: 'personal',
      });

      expect(memoriesService.update).toHaveBeenCalledWith('mem-1', {
        fact: 'New fact',
        category: 'personal',
      });
      expect(result).toEqual(updated);
    });

    it('throws NotFoundException when memory does not exist', async () => {
      memoriesService.update.mockRejectedValue(new NotFoundException('Memory not found'));

      await expect(
        controller.update('bad-id', { fact: 'Anything' }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('remove', () => {
    it('deletes a memory and returns undefined', async () => {
      memoriesService.remove.mockResolvedValue(undefined);

      const result = await controller.remove('mem-1');

      expect(memoriesService.remove).toHaveBeenCalledWith('mem-1');
      expect(result).toBeUndefined();
    });

    it('throws NotFoundException when memory does not exist', async () => {
      memoriesService.remove.mockRejectedValue(new NotFoundException('Memory not found'));

      await expect(controller.remove('bad-id')).rejects.toThrow(NotFoundException);
    });
  });
});
