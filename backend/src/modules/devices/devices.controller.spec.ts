import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { DevicesController } from './devices.controller';

describe('DevicesController', () => {
  let controller: DevicesController;
  let devicesService: Record<string, jest.Mock>;

  const mockUser = { userId: 'user-1', email: 'user@test.com' };

  const mockDevice = {
    id: 'device-1',
    userId: 'user-1',
    name: 'My Bot',
    deviceToken: 'tok-123',
    tokenRevoked: false,
    settingsJson: { volume: 80 },
    personalityJson: { tone: 'friendly' },
  };

  beforeEach(() => {
    devicesService = {
      create: jest.fn(),
      findAllByUser: jest.fn(),
      findById: jest.fn(),
      updateSettings: jest.fn(),
      claimByToken: jest.fn(),
      getStats: jest.fn(),
      remove: jest.fn(),
    };

    const mockGateway = { sendToDevice: jest.fn() };
    controller = new DevicesController(devicesService as any, mockGateway as any);
  });

  describe('create', () => {
    it('creates a device and returns it with token', async () => {
      const response = { device: mockDevice, deviceToken: 'tok-123' };
      devicesService.create.mockResolvedValue(response);

      const result = await controller.create(mockUser, { name: 'My Bot' });

      expect(devicesService.create).toHaveBeenCalledWith('user-1', { name: 'My Bot' });
      expect(result).toEqual(response);
    });
  });

  describe('findAll', () => {
    it('returns all devices for the authenticated user', async () => {
      devicesService.findAllByUser.mockResolvedValue([mockDevice]);

      const result = await controller.findAll(mockUser);

      expect(devicesService.findAllByUser).toHaveBeenCalledWith('user-1');
      expect(result).toEqual([mockDevice]);
    });

    it('returns empty array when user has no devices', async () => {
      devicesService.findAllByUser.mockResolvedValue([]);
      const result = await controller.findAll(mockUser);
      expect(result).toEqual([]);
    });
  });

  describe('findOne', () => {
    it('returns a device by id for the authenticated user', async () => {
      devicesService.findById.mockResolvedValue(mockDevice);

      const result = await controller.findOne('device-1', mockUser);

      expect(devicesService.findById).toHaveBeenCalledWith('device-1', 'user-1');
      expect(result).toEqual(mockDevice);
    });

    it('throws NotFoundException when device does not exist', async () => {
      devicesService.findById.mockRejectedValue(new NotFoundException('Device not found'));

      await expect(controller.findOne('bad-id', mockUser)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('throws ForbiddenException when device belongs to another user', async () => {
      devicesService.findById.mockRejectedValue(new ForbiddenException('Not your device'));

      await expect(controller.findOne('device-1', mockUser)).rejects.toThrow(
        ForbiddenException,
      );
    });
  });

  describe('updateSettings', () => {
    it('merges settings and returns updated device', async () => {
      const updated = { ...mockDevice, settingsJson: { volume: 80, brightness: 50 } };
      devicesService.updateSettings.mockResolvedValue(updated);

      const result = await controller.updateSettings(
        'device-1',
        mockUser,
        { brightness: 50 } as any,
      );

      expect(devicesService.updateSettings).toHaveBeenCalledWith(
        'device-1',
        'user-1',
        { brightness: 50 },
      );
      expect(result.settingsJson).toEqual({ volume: 80, brightness: 50 });
    });
  });

  describe('claim', () => {
    it('claims a device by token for the authenticated user', async () => {
      devicesService.claimByToken.mockResolvedValue(mockDevice);

      const result = await controller.claim(mockUser, { deviceToken: 'tok-123' });

      expect(devicesService.claimByToken).toHaveBeenCalledWith('user-1', 'tok-123');
      expect(result).toEqual(mockDevice);
    });

    it('throws NotFoundException when token is invalid', async () => {
      devicesService.claimByToken.mockRejectedValue(
        new NotFoundException('No device found with that token'),
      );

      await expect(
        controller.claim(mockUser, { deviceToken: 'bad-token' }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('getStats', () => {
    it('returns conversation and memory statistics for the device', async () => {
      const stats = {
        conversationsToday: 3,
        totalConversations: 42,
        totalMemories: 10,
        poolSize: 5,
      };
      devicesService.getStats.mockResolvedValue(stats);

      const result = await controller.getStats('device-1', mockUser);

      expect(devicesService.getStats).toHaveBeenCalledWith('device-1', 'user-1');
      expect(result).toEqual(stats);
    });
  });

  describe('remove', () => {
    it('removes the device and returns undefined', async () => {
      devicesService.remove.mockResolvedValue(undefined);

      const result = await controller.remove('device-1', mockUser);

      expect(devicesService.remove).toHaveBeenCalledWith('device-1', 'user-1');
      expect(result).toBeUndefined();
    });

    it('throws NotFoundException when device does not exist', async () => {
      devicesService.remove.mockRejectedValue(new NotFoundException('Device not found'));

      await expect(controller.remove('bad-id', mockUser)).rejects.toThrow(
        NotFoundException,
      );
    });
  });
});
