import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { randomUUID } from 'crypto';
import {
  Device,
  Conversation,
  Message,
  Memory,
  ResponsePool,
} from '../../core/database/entities';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateSettingsDto } from './dto/update-settings.dto';

@Injectable()
export class DevicesService {
  constructor(
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
    @InjectRepository(Conversation)
    private readonly convosRepo: Repository<Conversation>,
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
    @InjectRepository(Memory)
    private readonly memoriesRepo: Repository<Memory>,
    @InjectRepository(ResponsePool)
    private readonly poolRepo: Repository<ResponsePool>,
  ) {}

  async create(
    userId: string,
    dto: CreateDeviceDto,
  ): Promise<{ device: Device; deviceToken: string }> {
    const deviceToken = randomUUID();

    const device = this.devicesRepo.create({
      userId,
      name: dto.name ?? 'My Bot',
      deviceToken,
    });
    await this.devicesRepo.save(device);

    return { device, deviceToken };
  }

  async findAllByUser(userId: string): Promise<Device[]> {
    return this.devicesRepo.find({
      where: { userId },
      order: { createdAt: 'DESC' },
    });
  }

  async findById(id: string, userId: string): Promise<Device> {
    const device = await this.devicesRepo.findOne({ where: { id } });
    if (!device) throw new NotFoundException('Device not found');
    if (device.userId !== userId)
      throw new ForbiddenException('Not your device');
    return device;
  }

  async updateSettings(
    id: string,
    userId: string,
    dto: UpdateSettingsDto,
  ): Promise<Device> {
    const device = await this.findById(id, userId);
    device.settingsJson = { ...device.settingsJson, ...dto };
    return this.devicesRepo.save(device);
  }

  async getPersonality(
    id: string,
    userId: string,
  ): Promise<Record<string, any>> {
    const device = await this.findById(id, userId);
    return device.personalityJson;
  }

  async updatePersonality(
    id: string,
    userId: string,
    dto: Record<string, any>,
  ): Promise<Record<string, any>> {
    const device = await this.findById(id, userId);
    device.personalityJson = { ...device.personalityJson, ...dto };
    const saved = await this.devicesRepo.save(device);
    return saved.personalityJson;
  }

  async claimByToken(
    userId: string,
    deviceToken: string,
  ): Promise<Device> {
    const device = await this.devicesRepo.findOne({
      where: { deviceToken, tokenRevoked: false },
    });
    if (!device) {
      throw new NotFoundException(
        'No device found with that token. Make sure the device is powered on and the token is correct.',
      );
    }
    if (device.userId !== userId) {
      throw new ForbiddenException('This device belongs to another account');
    }
    return device;
  }

  async remove(id: string, userId: string): Promise<void> {
    const device = await this.findById(id, userId);
    device.tokenRevoked = true;
    await this.devicesRepo.save(device);
    await this.devicesRepo.remove(device);
  }

  async getStats(id: string, userId: string) {
    await this.findById(id, userId); // ownership check

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const [conversationsToday, totalConversations, totalMemories, poolCount] =
      await Promise.all([
        this.convosRepo
          .createQueryBuilder('c')
          .where('c.deviceId = :id', { id })
          .andWhere('c.startedAt >= :today', { today })
          .getCount(),
        this.convosRepo.count({ where: { deviceId: id } }),
        this.memoriesRepo.count({ where: { deviceId: id } }),
        this.poolRepo.count({ where: { deviceId: id } }),
      ]);

    return {
      conversationsToday,
      totalConversations,
      totalMemories,
      poolSize: poolCount,
    };
  }

  async findByToken(token: string): Promise<Device | null> {
    return this.devicesRepo.findOne({
      where: { deviceToken: token, tokenRevoked: false },
    });
  }
}
