import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Conversation, Message, Device } from '../../core/database/entities';

@Injectable()
export class ConversationsService {
  constructor(
    @InjectRepository(Conversation)
    private readonly conversationsRepo: Repository<Conversation>,
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
  ) {}

  async findByDevice(
    deviceId: string,
    userId: string,
    page = 1,
    limit = 20,
  ) {
    await this.assertDeviceOwnership(deviceId, userId);

    const [conversations, total] = await this.conversationsRepo.findAndCount({
      where: { deviceId },
      order: { startedAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });

    return {
      data: conversations,
      meta: { page, limit, total },
    };
  }

  async findMessages(
    conversationId: string,
    userId: string,
    page = 1,
    limit = 50,
  ) {
    // Verify ownership through conversation → device → user
    const conversation = await this.conversationsRepo.findOne({
      where: { id: conversationId },
      relations: ['device'],
    });

    if (!conversation) throw new NotFoundException('Conversation not found');
    if (conversation.device.userId !== userId) {
      throw new NotFoundException('Conversation not found');
    }

    const [messages, total] = await this.messagesRepo.findAndCount({
      where: { conversationId },
      order: { createdAt: 'ASC' },
      skip: (page - 1) * limit,
      take: limit,
    });

    return {
      data: messages,
      meta: { page, limit, total },
    };
  }

  private async assertDeviceOwnership(
    deviceId: string,
    userId: string,
  ): Promise<void> {
    const device = await this.devicesRepo.findOne({
      where: { id: deviceId },
    });
    if (!device || device.userId !== userId) {
      throw new NotFoundException('Device not found');
    }
  }
}
