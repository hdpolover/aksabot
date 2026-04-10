import { NotFoundException } from '@nestjs/common';
import { ConversationsController } from './conversations.controller';

describe('ConversationsController', () => {
  let controller: ConversationsController;
  let conversationsService: Record<string, jest.Mock>;

  const mockUser = { userId: 'user-1', email: 'user@test.com' };

  const mockConversation = {
    id: 'conv-1',
    deviceId: 'device-1',
    startedAt: new Date(),
    endedAt: new Date(),
  };

  const mockMessage = {
    id: 'msg-1',
    conversationId: 'conv-1',
    role: 'user',
    content: 'Hello bot',
    createdAt: new Date(),
  };

  beforeEach(() => {
    conversationsService = {
      findByDevice: jest.fn(),
      findMessages: jest.fn(),
    };

    controller = new ConversationsController(conversationsService as any);
  });

  describe('findByDevice', () => {
    it('returns paginated conversations for a device', async () => {
      const response = {
        data: [mockConversation],
        meta: { page: 1, limit: 20, total: 1 },
      };
      conversationsService.findByDevice.mockResolvedValue(response);

      const result = await controller.findByDevice('device-1', mockUser);

      expect(conversationsService.findByDevice).toHaveBeenCalledWith(
        'device-1',
        'user-1',
        1,
        20,
      );
      expect(result).toEqual(response);
    });

    it('parses page and limit query params', async () => {
      conversationsService.findByDevice.mockResolvedValue({
        data: [],
        meta: { page: 2, limit: 10, total: 0 },
      });

      await controller.findByDevice('device-1', mockUser, '2', '10');

      expect(conversationsService.findByDevice).toHaveBeenCalledWith(
        'device-1',
        'user-1',
        2,
        10,
      );
    });

    it('falls back to defaults when page and limit are not provided', async () => {
      conversationsService.findByDevice.mockResolvedValue({
        data: [],
        meta: { page: 1, limit: 20, total: 0 },
      });

      await controller.findByDevice('device-1', mockUser, undefined, undefined);

      expect(conversationsService.findByDevice).toHaveBeenCalledWith(
        'device-1',
        'user-1',
        1,
        20,
      );
    });

    it('throws NotFoundException when device does not exist or is not owned', async () => {
      conversationsService.findByDevice.mockRejectedValue(
        new NotFoundException('Device not found'),
      );

      await expect(
        controller.findByDevice('bad-device', mockUser),
      ).rejects.toThrow(NotFoundException);
    });

    it('returns empty data when device has no conversations', async () => {
      conversationsService.findByDevice.mockResolvedValue({
        data: [],
        meta: { page: 1, limit: 20, total: 0 },
      });

      const result = await controller.findByDevice('device-1', mockUser);
      expect(result.data).toEqual([]);
      expect(result.meta.total).toBe(0);
    });
  });

  describe('findMessages', () => {
    it('returns paginated messages for a conversation', async () => {
      const response = {
        data: [mockMessage],
        meta: { page: 1, limit: 50, total: 1 },
      };
      conversationsService.findMessages.mockResolvedValue(response);

      const result = await controller.findMessages('conv-1', mockUser);

      expect(conversationsService.findMessages).toHaveBeenCalledWith(
        'conv-1',
        'user-1',
        1,
        50,
      );
      expect(result).toEqual(response);
    });

    it('parses page and limit query params', async () => {
      conversationsService.findMessages.mockResolvedValue({
        data: [],
        meta: { page: 3, limit: 25, total: 0 },
      });

      await controller.findMessages('conv-1', mockUser, '3', '25');

      expect(conversationsService.findMessages).toHaveBeenCalledWith(
        'conv-1',
        'user-1',
        3,
        25,
      );
    });

    it('falls back to defaults when page and limit are not provided', async () => {
      conversationsService.findMessages.mockResolvedValue({
        data: [],
        meta: { page: 1, limit: 50, total: 0 },
      });

      await controller.findMessages('conv-1', mockUser, undefined, undefined);

      expect(conversationsService.findMessages).toHaveBeenCalledWith(
        'conv-1',
        'user-1',
        1,
        50,
      );
    });

    it('throws NotFoundException when conversation does not exist', async () => {
      conversationsService.findMessages.mockRejectedValue(
        new NotFoundException('Conversation not found'),
      );

      await expect(
        controller.findMessages('bad-conv', mockUser),
      ).rejects.toThrow(NotFoundException);
    });

    it('returns both user and assistant messages in order', async () => {
      const messages = [
        { ...mockMessage, role: 'user', content: 'Hello' },
        { ...mockMessage, id: 'msg-2', role: 'assistant', content: 'Hi!' },
      ];
      conversationsService.findMessages.mockResolvedValue({
        data: messages,
        meta: { page: 1, limit: 50, total: 2 },
      });

      const result = await controller.findMessages('conv-1', mockUser);
      expect(result.data).toHaveLength(2);
      expect(result.data[0].role).toBe('user');
      expect(result.data[1].role).toBe('assistant');
    });
  });
});
