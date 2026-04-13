import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { EmailService } from '../../core/email/email.service';

describe('AuthService', () => {
  let service: AuthService;
  let usersRepo: Record<string, jest.Mock>;
  let devicesRepo: Record<string, jest.Mock>;
  let jwtService: Partial<JwtService>;

  const mockUser = {
    id: 'user-1',
    email: 'test@example.com',
    passwordHash: '',
    name: 'Test User',
  };

  beforeEach(async () => {
    mockUser.passwordHash = await bcrypt.hash('password123', 4); // low rounds for speed

    usersRepo = {
      findOne: jest.fn(),
      create: jest.fn().mockReturnValue(mockUser),
      save: jest.fn().mockResolvedValue(mockUser),
    };

    devicesRepo = {
      findOne: jest.fn(),
    };

    jwtService = {
      signAsync: jest.fn().mockResolvedValue('mock-token'),
      verify: jest.fn().mockReturnValue({ sub: 'user-1', email: 'test@example.com' }),
    };

    const configService = {
      get: jest.fn().mockReturnValue('30d'),
    } as unknown as ConfigService;

    const emailService = {
      sendPasswordReset: jest.fn().mockResolvedValue(undefined),
    } as unknown as EmailService;

    service = new AuthService(
      usersRepo as any,
      devicesRepo as any,
      jwtService as JwtService,
      configService,
      emailService,
    );
  });

  describe('register', () => {
    it('creates a new user and returns tokens', async () => {
      usersRepo.findOne.mockResolvedValue(null); // no existing user

      const result = await service.register({
        email: 'test@example.com',
        password: 'password123',
        name: 'Test User',
      });

      expect(result.accessToken).toBe('mock-token');
      expect(result.refreshToken).toBe('mock-token');
      expect(result.user.email).toBe('test@example.com');
      expect(usersRepo.create).toHaveBeenCalled();
      expect(usersRepo.save).toHaveBeenCalled();
    });

    it('throws ConflictException if email already exists', async () => {
      usersRepo.findOne.mockResolvedValue(mockUser);

      await expect(
        service.register({
          email: 'test@example.com',
          password: 'password123',
          name: 'Test User',
        }),
      ).rejects.toThrow(ConflictException);
    });
  });

  describe('login', () => {
    it('returns tokens for valid credentials', async () => {
      usersRepo.findOne.mockResolvedValue(mockUser);

      const result = await service.login({
        email: 'test@example.com',
        password: 'password123',
      });

      expect(result.accessToken).toBe('mock-token');
      expect(result.user.id).toBe('user-1');
    });

    it('throws UnauthorizedException for unknown email', async () => {
      usersRepo.findOne.mockResolvedValue(null);

      await expect(
        service.login({ email: 'bad@example.com', password: 'password123' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('throws UnauthorizedException for wrong password', async () => {
      usersRepo.findOne.mockResolvedValue(mockUser);

      await expect(
        service.login({ email: 'test@example.com', password: 'wrong' }),
      ).rejects.toThrow(UnauthorizedException);
    });
  });

  describe('refresh', () => {
    it('returns new tokens for valid refresh token', async () => {
      usersRepo.findOne.mockResolvedValue(mockUser);

      const result = await service.refresh('valid-refresh-token');
      expect(result.accessToken).toBe('mock-token');
    });

    it('throws UnauthorizedException for invalid refresh token', async () => {
      (jwtService.verify as jest.Mock).mockImplementation(() => {
        throw new Error('invalid');
      });

      await expect(service.refresh('bad-token')).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('throws UnauthorizedException if user no longer exists', async () => {
      usersRepo.findOne.mockResolvedValue(null);

      await expect(service.refresh('valid-token')).rejects.toThrow(
        UnauthorizedException,
      );
    });
  });

  describe('validateDeviceToken', () => {
    it('returns device and userId for valid token', async () => {
      const mockDevice = {
        id: 'device-1',
        userId: 'user-1',
        deviceToken: 'tok-123',
        tokenRevoked: false,
        user: mockUser,
      };
      devicesRepo.findOne.mockResolvedValue(mockDevice);

      const result = await service.validateDeviceToken('tok-123');
      expect(result).toEqual({
        device: mockDevice,
        userId: 'user-1',
      });
    });

    it('returns null for invalid token', async () => {
      devicesRepo.findOne.mockResolvedValue(null);
      const result = await service.validateDeviceToken('bad-token');
      expect(result).toBeNull();
    });
  });
});
