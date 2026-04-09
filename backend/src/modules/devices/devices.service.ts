import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { randomUUID } from 'crypto';
import { Device } from '../../core/database/entities';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateSettingsDto } from './dto/update-settings.dto';

@Injectable()
export class DevicesService {
  constructor(
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
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

  async remove(id: string, userId: string): Promise<void> {
    const device = await this.findById(id, userId);
    device.tokenRevoked = true;
    await this.devicesRepo.save(device);
    await this.devicesRepo.remove(device);
  }

  async findByToken(token: string): Promise<Device | null> {
    return this.devicesRepo.findOne({
      where: { deviceToken: token, tokenRevoked: false },
    });
  }
}
