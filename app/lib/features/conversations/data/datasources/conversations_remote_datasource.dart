import '../../../../core/network/api_client.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

class ConversationsRemoteDatasource {
  final ApiClient _client;

  ConversationsRemoteDatasource(this._client);

  Future<List<ConversationModel>> getConversations(String deviceId) async {
    final data = await _client.get('/devices/$deviceId/conversations');
    final list = data as List;
    return list
        .map((json) =>
            ConversationModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<MessageModel>> getMessages(String conversationId) async {
    final data = await _client.get('/conversations/$conversationId/messages');
    final list = data as List;
    return list
        .map((json) => MessageModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteConversation(String conversationId) async {
    await _client.delete('/conversations/$conversationId');
  }
}
