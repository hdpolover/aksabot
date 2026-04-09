import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Conversation, Message, Device } from '../../core/database/entities';

@Injectable()
export class ConversationPersistence {
  constructor(
    @InjectRepository(Conversation)
    private readonly conversationsRepo: Repository<Conversation>,
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
  ) {}

  async createConversation(deviceId: string): Promise<Conversation> {
    const conversation = this.conversationsRepo.create({ deviceId });
    return this.conversationsRepo.save(conversation);
  }

  async endConversation(conversationId: string): Promise<void> {
    await this.conversationsRepo.update(conversationId, {
      endedAt: new Date(),
    });
  }

  async saveMessage(
    conversationId: string,
    role: 'user' | 'assistant',
    content: string,
  ): Promise<Message> {
    const message = this.messagesRepo.create({
      conversationId,
      role,
      content,
    });
    return this.messagesRepo.save(message);
  }

  async getRecentHistory(
    conversationId: string,
    limit = 20,
  ): Promise<{ role: string; content: string }[]> {
    const messages = await this.messagesRepo.find({
      where: { conversationId },
      order: { createdAt: 'ASC' },
      take: limit,
    });
    return messages.map((m) => ({ role: m.role, content: m.content }));
  }

  async getDevice(deviceId: string): Promise<Device | null> {
    return this.devicesRepo.findOne({ where: { id: deviceId } });
  }

  async updateLastSeen(deviceId: string): Promise<void> {
    await this.devicesRepo.update(deviceId, { lastSeenAt: new Date() });
  }
}
