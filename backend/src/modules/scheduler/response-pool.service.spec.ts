import { ResponsePoolService } from './response-pool.service';

describe('ResponsePoolService', () => {
  let service: ResponsePoolService;
  let repo: Record<string, jest.Mock>;
  let mockLlm: { generate: jest.Mock };

  beforeEach(() => {
    repo = {
      findOne: jest.fn(),
      find: jest.fn().mockResolvedValue([]),
      create: jest.fn().mockImplementation((data) => ({ id: 'rp-1', useCount: 0, ...data })),
      save: jest.fn().mockImplementation((data) => Promise.resolve(Array.isArray(data) ? data : data)),
      count: jest.fn().mockResolvedValue(0),
      update: jest.fn().mockResolvedValue({ affected: 1 }),
      delete: jest.fn().mockResolvedValue({ affected: 5 }),
      createQueryBuilder: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnThis(),
        addSelect: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        groupBy: jest.fn().mockReturnThis(),
        getRawMany: jest.fn().mockResolvedValue([]),
      }),
    };

    mockLlm = {
      generate: jest.fn().mockResolvedValue({
        text: 'Time to stand!\nDrink water!\nStretch it out!',
      }),
    };

    service = new ResponsePoolService(repo as any, mockLlm as any);
  });

  describe('pickLru', () => {
    it('returns and bumps existing response', async () => {
      const existing = {
        id: 'rp-1',
        text: 'Stand up!',
        useCount: 2,
        lastAccessedAt: null,
      };
      repo.findOne.mockResolvedValue(existing);

      const result = await service.pickLru('device-1', 'stand_up');
      expect(result.text).toBe('Stand up!');
      expect(result.useCount).toBe(3);
      expect(repo.save).toHaveBeenCalled();
    });

    it('generates on the fly when pool is empty', async () => {
      repo.findOne.mockResolvedValue(null);

      const result = await service.pickLru('device-1', 'stand_up');
      expect(mockLlm.generate).toHaveBeenCalled();
      expect(repo.save).toHaveBeenCalled();
    });
  });

  describe('generateAndStore', () => {
    it('generates entries and saves them', async () => {
      const result = await service.generateAndStore('device-1', 'hydration', 3);
      expect(mockLlm.generate).toHaveBeenCalled();
      expect(repo.create).toHaveBeenCalledTimes(3);
      expect(repo.save).toHaveBeenCalled();
    });

    it('returns empty on unknown category', async () => {
      const result = await service.generateAndStore('device-1', 'unknown_cat', 3);
      expect(result).toEqual([]);
      expect(mockLlm.generate).not.toHaveBeenCalled();
    });

    it('returns empty on LLM error', async () => {
      mockLlm.generate.mockRejectedValue(new Error('API error'));
      const result = await service.generateAndStore('device-1', 'hydration', 3);
      expect(result).toEqual([]);
    });
  });

  describe('refillIfNeeded', () => {
    it('generates entries for empty categories', async () => {
      repo.count.mockResolvedValue(0);
      await service.refillIfNeeded('device-1');
      // Should have called generate for all categories
      expect(mockLlm.generate).toHaveBeenCalled();
    });

    it('skips full categories', async () => {
      repo.count.mockResolvedValue(100);
      await service.refillIfNeeded('device-1');
      expect(mockLlm.generate).not.toHaveBeenCalled();
    });
  });

  describe('clearForDevice', () => {
    it('deletes all pool entries', async () => {
      await service.clearForDevice('device-1');
      expect(repo.delete).toHaveBeenCalledWith({ deviceId: 'device-1' });
    });
  });
});
