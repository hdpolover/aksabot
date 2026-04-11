import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { DevicesService } from './devices.service';

describe('DevicesService', () => {
  let service: DevicesService;
  let repo: Record<string, jest.Mock>;

  const mockDevice = {
    id: 'device-1',
    userId: 'user-1',
    name: 'My Bot',
    deviceToken: 'tok-123',
    tokenRevoked: false,
    settingsJson: {},
    personalityJson: {},
  };

  beforeEach(() => {
    repo = {
      create: jest.fn().mockImplementation((data) => ({ ...mockDevice, ...data })),
      save: jest.fn().mockImplementation((device) => Promise.resolve(device)),
      find: jest.fn().mockResolvedValue([mockDevice]),
      findOne: jest.fn(),
      remove: jest.fn().mockResolvedValue(undefined),
    };

    const emptyRepo = {} as any;
    service = new DevicesService(repo as any, emptyRepo, emptyRepo, emptyRepo, emptyRepo);
  });

  describe('create', () => {
    it('creates a device with generated token', async () => {
      const result = await service.create('user-1', { name: 'Test Bot' });

      expect(result.device.name).toBe('Test Bot');
      expect(result.deviceToken).toBeDefined();
      expect(typeof result.deviceToken).toBe('string');
      expect(repo.save).toHaveBeenCalled();
    });

    it('uses default name when not provided', async () => {
      const result = await service.create('user-1', {});
      expect(result.device.name).toBe('My Bot');
    });
  });

  describe('findAllByUser', () => {
    it('returns devices for user', async () => {
      const result = await service.findAllByUser('user-1');
      expect(result).toEqual([mockDevice]);
      expect(repo.find).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        order: { createdAt: 'DESC' },
      });
    });
  });

  describe('findById', () => {
    it('returns device if owned by user', async () => {
      repo.findOne.mockResolvedValue(mockDevice);
      const result = await service.findById('device-1', 'user-1');
      expect(result.id).toBe('device-1');
    });

    it('throws NotFoundException if device does not exist', async () => {
      repo.findOne.mockResolvedValue(null);
      await expect(service.findById('bad-id', 'user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('throws ForbiddenException if device belongs to another user', async () => {
      repo.findOne.mockResolvedValue(mockDevice);
      await expect(service.findById('device-1', 'other-user')).rejects.toThrow(
        ForbiddenException,
      );
    });
  });

  describe('updateSettings', () => {
    it('merges settings and saves', async () => {
      repo.findOne.mockResolvedValue({ ...mockDevice, settingsJson: { volume: 80 } });
      const result = await service.updateSettings('device-1', 'user-1', {
        brightness: 50,
      } as any);
      expect(result.settingsJson).toEqual({ volume: 80, brightness: 50 });
    });
  });

  describe('remove', () => {
    it('revokes token and removes device', async () => {
      repo.findOne.mockResolvedValue({ ...mockDevice });
      await service.remove('device-1', 'user-1');
      expect(repo.save).toHaveBeenCalledWith(
        expect.objectContaining({ tokenRevoked: true }),
      );
      expect(repo.remove).toHaveBeenCalled();
    });
  });
});
