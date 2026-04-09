import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { randomBytes } from 'crypto';
import { User } from '../database/entities';
import { Device } from '../database/entities';
import { RegisterDto, LoginDto } from './dto';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface AuthResponse extends TokenPair {
  user: { id: string; email: string; name: string };
}

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private readonly usersRepo: Repository<User>,
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
    private readonly jwtService: JwtService,
    private readonly config: ConfigService,
  ) {}

  async register(dto: RegisterDto): Promise<AuthResponse> {
    const existing = await this.usersRepo.findOne({
      where: { email: dto.email },
    });
    if (existing) {
      throw new ConflictException('Email already registered');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);

    const user = this.usersRepo.create({
      email: dto.email,
      passwordHash,
      name: dto.name,
    });
    await this.usersRepo.save(user);

    const tokens = await this.generateTokens(user);

    return {
      ...tokens,
      user: { id: user.id, email: user.email, name: user.name },
    };
  }

  async login(dto: LoginDto): Promise<AuthResponse> {
    const user = await this.usersRepo.findOne({
      where: { email: dto.email },
    });
    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const passwordMatch = await bcrypt.compare(dto.password, user.passwordHash);
    if (!passwordMatch) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const tokens = await this.generateTokens(user);

    return {
      ...tokens,
      user: { id: user.id, email: user.email, name: user.name },
    };
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    try {
      const payload = this.jwtService.verify(refreshToken, {
        secret: this.config.get<string>('JWT_SECRET'),
      });

      const user = await this.usersRepo.findOne({
        where: { id: payload.sub },
      });
      if (!user) {
        throw new UnauthorizedException('User not found');
      }

      return this.generateTokens(user);
    } catch {
      throw new UnauthorizedException('Invalid refresh token');
    }
  }

  async validateDeviceToken(
    token: string,
  ): Promise<{ device: Device; userId: string } | null> {
    const device = await this.devicesRepo.findOne({
      where: { deviceToken: token, tokenRevoked: false },
      relations: ['user'],
    });

    if (!device) return null;

    return { device, userId: device.userId };
  }

  private async generateTokens(user: User): Promise<TokenPair> {
    const payload = { sub: user.id, email: user.email };

    const [accessToken, refreshToken] = await Promise.all([
      this.jwtService.signAsync(payload),
      this.jwtService.signAsync(payload, {
        expiresIn: this.config.get<string>('JWT_REFRESH_EXPIRY', '30d') as any,
      }),
    ]);

    return { accessToken, refreshToken };
  }
}
