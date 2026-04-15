import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, Repository } from 'typeorm';
import { Conversation, Message, Device } from '../../core/database/entities';

@Injectable()
export class ConversationPersistence {
  private readonly logger = new Logger(ConversationPersistence.name);

  constructor(
    @InjectRepository(Conversation)
    private readonly conversationsRepo: Repository<Conversation>,
    @InjectRepository(Message)
    private readonly messagesRepo: Repository<Message>,
    @InjectRepository(Device)
    private readonly devicesRepo: Repository<Device>,
  ) {}

  async createConversation(deviceId: string): Promise<Conversation> {
    // Find stale open conversations so we can return their IDs for memory extraction
    const staleConversations = await this.conversationsRepo.find({
      where: { deviceId, endedAt: IsNull() },
      select: ['id'],
    });

    if (staleConversations.length > 0) {
      await this.conversationsRepo.update(
        { deviceId, endedAt: IsNull() },
        { endedAt: new Date() },
      );
      this.logger.log(
        `Closed ${staleConversations.length} stale conversation(s) for device ${deviceId}`,
      );
    }

    const conversation = this.conversationsRepo.create({ deviceId });
    const saved = await this.conversationsRepo.save(conversation);
    // Attach closed conversation IDs for callers that need them (e.g. memory extraction)
    (saved as any).closedConversationIds = staleConversations.map((c) => c.id);
    return saved;
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
    limit = 10,
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

  async updateDeviceInfo(
    deviceId: string,
    info: { firmwareVersion?: string; wifiSsid?: string; wifiRssi?: number },
  ): Promise<void> {
    const device = await this.devicesRepo.findOne({ where: { id: deviceId } });
    if (!device) return;

    if (info.firmwareVersion) device.firmwareVersion = info.firmwareVersion;
    if (info.wifiSsid) device.wifiSsid = info.wifiSsid;
    // RSSI stored in settingsJson (no dedicated column — avoids migration)
    if (info.wifiRssi !== undefined) {
      device.settingsJson = {
        ...device.settingsJson,
        wifi_rssi: info.wifiRssi,
      };
    }
    await this.devicesRepo.save(device);
  }
}
