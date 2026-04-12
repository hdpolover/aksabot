import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversations_repository.dart';
import '../datasources/conversations_remote_datasource.dart';

class ConversationsRepositoryImpl implements ConversationsRepository {
  final ConversationsRemoteDatasource _datasource;

  ConversationsRepositoryImpl(this._datasource);

  @override
  Future<Either<Failure, List<Conversation>>> getConversations(
    String deviceId,
  ) async {
    try {
      final conversations = await _datasource.getConversations(deviceId);
      return Right(conversations);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, List<Message>>> getMessages(
    String conversationId,
  ) async {
    try {
      final messages = await _datasource.getMessages(conversationId);
      return Right(messages);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> deleteConversation(
    String conversationId,
  ) async {
    try {
      await _datasource.deleteConversation(conversationId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }
}
