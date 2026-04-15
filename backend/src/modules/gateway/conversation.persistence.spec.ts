import { ConversationPersistence } from './conversation.persistence';

describe('ConversationPersistence', () => {
  let service: ConversationPersistence;
  let conversationsRepo: Record<string, jest.Mock>;
  let messagesRepo: Record<string, jest.Mock>;
  let devicesRepo: Record<string, jest.Mock>;

  const mockConversation = {
    id: 'conv-1',
    deviceId: 'device-1',
    startedAt: new Date(),
    endedAt: null,
  };

  const mockMessage = {
    id: 'msg-1',
    conversationId: 'conv-1',
    role: 'user' as const,
    content: 'Hello bot',
    createdAt: new Date(),
  };

  const mockDevice = {
    id: 'device-1',
    userId: 'user-1',
    name: 'My Bot',
    personalityJson: { tone: 'friendly' },
    lastSeenAt: null,
  };

  beforeEach(() => {
    conversationsRepo = {
      create: jest
        .fn()
        .mockImplementation((data) => ({ ...mockConversation, ...data })),
      save: jest.fn().mockImplementation((entity) => Promise.resolve(entity)),
      update: jest.fn().mockResolvedValue({ affected: 1 }),
    };

    messagesRepo = {
      create: jest
        .fn()
        .mockImplementation((data) => ({ ...mockMessage, ...data })),
      save: jest.fn().mockImplementation((entity) => Promise.resolve(entity)),
      find: jest.fn().mockResolvedValue([mockMessage]),
    };

    devicesRepo = {
      findOne: jest.fn().mockResolvedValue(mockDevice),
      update: jest.fn().mockResolvedValue({ affected: 1 }),
    };

    service = new ConversationPersistence(
      conversationsRepo as any,
      messagesRepo as any,
      devicesRepo as any,
    );
  });

  describe('createConversation', () => {
    it('creates and saves a conversation for the given device', async () => {
      const result = await service.createConversation('device-1');

      expect(conversationsRepo.create).toHaveBeenCalledWith({
        deviceId: 'device-1',
      });
      expect(conversationsRepo.save).toHaveBeenCalled();
      expect(result.deviceId).toBe('device-1');
    });

    it('returns the saved conversation entity', async () => {
      const saved = { ...mockConversation, id: 'conv-new' };
      conversationsRepo.save.mockResolvedValue(saved);

      const result = await service.createConversation('device-1');
      expect(result.id).toBe('conv-new');
    });
  });

  describe('endConversation', () => {
    it('sets endedAt to current time on the conversation', async () => {
      await service.endConversation('conv-1');

      expect(conversationsRepo.update).toHaveBeenCalledWith(
        'conv-1',
        expect.objectContaining({ endedAt: expect.any(Date) }),
      );
    });

    it('resolves without throwing', async () => {
      await expect(service.endConversation('conv-1')).resolves.toBeUndefined();
    });
  });

  describe('saveMessage', () => {
    it('creates and saves a user message', async () => {
      const result = await service.saveMessage('conv-1', 'user', 'Hello bot');

      expect(messagesRepo.create).toHaveBeenCalledWith({
        conversationId: 'conv-1',
        role: 'user',
        content: 'Hello bot',
      });
      expect(messagesRepo.save).toHaveBeenCalled();
      expect(result.role).toBe('user');
      expect(result.content).toBe('Hello bot');
    });

    it('creates and saves an assistant message', async () => {
      messagesRepo.create.mockImplementation((data) => ({
        ...mockMessage,
        ...data,
      }));
      const result = await service.saveMessage(
        'conv-1',
        'assistant',
        'Hi there!',
      );

      expect(messagesRepo.create).toHaveBeenCalledWith({
        conversationId: 'conv-1',
        role: 'assistant',
        content: 'Hi there!',
      });
      expect(result.role).toBe('assistant');
    });
  });

  describe('getRecentHistory', () => {
    it('returns messages mapped to role/content pairs', async () => {
      messagesRepo.find.mockResolvedValue([
        { role: 'user', content: 'Hello', createdAt: new Date() },
        { role: 'assistant', content: 'Hi!', createdAt: new Date() },
      ]);

      const result = await service.getRecentHistory('conv-1');

      expect(result).toEqual([
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi!' },
      ]);
    });

    it('queries with correct conversation filter and ordering', async () => {
      await service.getRecentHistory('conv-1');

      expect(messagesRepo.find).toHaveBeenCalledWith({
        where: { conversationId: 'conv-1' },
        order: { createdAt: 'ASC' },
        take: 10,
      });
    });

    it('respects custom limit', async () => {
      await service.getRecentHistory('conv-1', 5);

      expect(messagesRepo.find).toHaveBeenCalledWith(
        expect.objectContaining({ take: 5 }),
      );
    });

    it('returns empty array when no messages exist', async () => {
      messagesRepo.find.mockResolvedValue([]);
      const result = await service.getRecentHistory('conv-1');
      expect(result).toEqual([]);
    });
  });

  describe('getDevice', () => {
    it('returns the device by id', async () => {
      const result = await service.getDevice('device-1');

      expect(devicesRepo.findOne).toHaveBeenCalledWith({
        where: { id: 'device-1' },
      });
      expect(result).toEqual(mockDevice);
    });

    it('returns null when device does not exist', async () => {
      devicesRepo.findOne.mockResolvedValue(null);
      const result = await service.getDevice('nonexistent');
      expect(result).toBeNull();
    });
  });

  describe('updateLastSeen', () => {
    it('updates lastSeenAt for the device', async () => {
      await service.updateLastSeen('device-1');

      expect(devicesRepo.update).toHaveBeenCalledWith(
        'device-1',
        expect.objectContaining({ lastSeenAt: expect.any(Date) }),
      );
    });

    it('resolves without throwing', async () => {
      await expect(service.updateLastSeen('device-1')).resolves.toBeUndefined();
    });
  });
});
