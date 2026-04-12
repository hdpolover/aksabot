import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/conversation_entity.dart';
import '../entities/message_entity.dart';

abstract class ConversationsRepository {
  Future<Either<Failure, List<Conversation>>> getConversations(String deviceId);
  Future<Either<Failure, List<Message>>> getMessages(String conversationId);
  Future<Either<Failure, void>> deleteConversation(String conversationId);
}
