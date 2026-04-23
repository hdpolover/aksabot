import { Test, TestingModule } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import { getRepositoryToken } from '@nestjs/typeorm';
import { VisionService } from './vision.service';
import { VisionInferenceService } from './vision-inference.service';
import { FaceProfile } from '../../core/database/entities/face-profile.entity';

const mockInference = {
  detect: jest.fn(),
  embed: jest.fn(),
};

const mockRepo = {
  find: jest.fn(),
  findOne: jest.fn(),
  create: jest.fn(),
  save: jest.fn(),
  delete: jest.fn(),
};

const mockDataSource = {
  query: jest.fn(),
};

describe('VisionService', () => {
  let service: VisionService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        VisionService,
        { provide: VisionInferenceService, useValue: mockInference },
        { provide: getRepositoryToken(FaceProfile), useValue: mockRepo },
        { provide: DataSource, useValue: mockDataSource },
      ],
    }).compile();
    service = module.get(VisionService);
    jest.clearAllMocks();
  });

  describe('enroll', () => {
    it('should detect face, compute embedding, and save profile', async () => {
      const fakeEmbedding = new Array(512).fill(0.1);
      mockInference.detect.mockResolvedValue({ box: [10, 10, 100, 100], score: 0.9 });
      mockInference.embed.mockResolvedValue(fakeEmbedding);
      mockRepo.create.mockReturnValue({ name: 'Hendra', userId: 'u1', embedding: fakeEmbedding });
      mockRepo.save.mockResolvedValue({ id: 'fp-uuid', name: 'Hendra' });

      const result = await service.enroll('u1', 'Hendra', [Buffer.from('jpeg')]);
      expect(mockInference.detect).toHaveBeenCalledTimes(1);
      expect(mockInference.embed).toHaveBeenCalledTimes(1);
      expect(mockRepo.save).toHaveBeenCalledTimes(1);
      expect(result.name).toBe('Hendra');
    });

    it('should throw if no face detected in any frame', async () => {
      mockInference.detect.mockResolvedValue(null);
      await expect(service.enroll('u1', 'Hendra', [Buffer.from('jpeg')])).rejects.toThrow(
        'No face detected',
      );
    });
  });

  describe('findBestMatch', () => {
    it('should return name when distance below threshold', async () => {
      mockDataSource.query.mockResolvedValue([{ id: 'fp1', name: 'Hendra', distance: '0.3' }]);
      const result = await service.findBestMatch('u1', new Array(512).fill(0.1));
      expect(result).toEqual({ name: 'Hendra', confidence: expect.any(Number), unknown: false });
    });

    it('should return unknown when distance above threshold', async () => {
      mockDataSource.query.mockResolvedValue([{ id: 'fp1', name: 'Hendra', distance: '0.55' }]);
      const result = await service.findBestMatch('u1', new Array(512).fill(0.1));
      expect(result).toEqual({ name: null, confidence: expect.any(Number), unknown: true });
    });

    it('should return unknown when no profiles exist', async () => {
      mockDataSource.query.mockResolvedValue([]);
      const result = await service.findBestMatch('u1', new Array(512).fill(0.1));
      expect(result).toEqual({ name: null, confidence: 0, unknown: true });
    });
  });

  describe('getProfiles', () => {
    it('should return profiles for user', async () => {
      mockRepo.find.mockResolvedValue([{ id: 'fp1', name: 'Hendra' }]);
      const result = await service.getProfiles('u1');
      expect(mockRepo.find).toHaveBeenCalledWith({ where: { userId: 'u1' }, order: { createdAt: 'ASC' } });
      expect(result).toHaveLength(1);
    });
  });

  describe('deleteProfile', () => {
    it('should delete when owned by user', async () => {
      mockRepo.findOne.mockResolvedValue({ id: 'fp1', userId: 'u1' });
      mockRepo.delete.mockResolvedValue({ affected: 1 });
      await service.deleteProfile('u1', 'fp1');
      expect(mockRepo.delete).toHaveBeenCalledWith('fp1');
    });

    it('should throw when profile not found or wrong user', async () => {
      mockRepo.findOne.mockResolvedValue(null);
      await expect(service.deleteProfile('u1', 'fp1')).rejects.toThrow();
    });
  });
});
