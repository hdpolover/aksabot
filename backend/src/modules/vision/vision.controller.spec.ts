import { Test, TestingModule } from '@nestjs/testing';
import { VisionController } from './vision.controller';
import { VisionService } from './vision.service';
import { AudioGateway } from '../gateway/audio.gateway';

const mockVisionService = {
  enroll: jest.fn(),
  getProfiles: jest.fn(),
  deleteProfile: jest.fn(),
};

const mockGateway = {
  sendVisionCapture: jest.fn(),
  setPendingEnrollment: jest.fn(),
};

const mockUser = { id: 'user-uuid', email: 'test@test.com' };

describe('VisionController', () => {
  let controller: VisionController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [VisionController],
      providers: [
        { provide: VisionService, useValue: mockVisionService },
        { provide: AudioGateway, useValue: mockGateway },
      ],
    }).compile();
    controller = module.get(VisionController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  describe('getProfiles', () => {
    it('should return profiles for current user', async () => {
      mockVisionService.getProfiles.mockResolvedValue([{ id: 'fp1', name: 'Hendra' }]);
      const result = await controller.getProfiles({ user: mockUser } as any);
      expect(mockVisionService.getProfiles).toHaveBeenCalledWith('user-uuid');
      expect(result).toHaveLength(1);
    });
  });

  describe('deleteProfile', () => {
    it('should delete profile', async () => {
      mockVisionService.deleteProfile.mockResolvedValue(undefined);
      await controller.deleteProfile({ user: mockUser } as any, 'fp1');
      expect(mockVisionService.deleteProfile).toHaveBeenCalledWith('user-uuid', 'fp1');
    });
  });
});
