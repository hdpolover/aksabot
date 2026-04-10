import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversations_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class ConversationsEvent extends Equatable {
  const ConversationsEvent();

  @override
  List<Object?> get props => [];
}

class LoadConversations extends ConversationsEvent {
  final String deviceId;
  const LoadConversations(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

class LoadMessages extends ConversationsEvent {
  final String conversationId;
  const LoadMessages(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class ConversationsState extends Equatable {
  const ConversationsState();

  @override
  List<Object?> get props => [];
}

class ConversationsInitial extends ConversationsState {
  const ConversationsInitial();
}

class ConversationsLoading extends ConversationsState {
  const ConversationsLoading();
}

class ConversationsLoaded extends ConversationsState {
  final List<Conversation> conversations;
  final Map<String, List<Message>> messagesCache;

  const ConversationsLoaded(this.conversations, {this.messagesCache = const {}});

  ConversationsLoaded copyWithMessages(
    String conversationId,
    List<Message> messages,
  ) {
    return ConversationsLoaded(
      conversations,
      messagesCache: {...messagesCache, conversationId: messages},
    );
  }

  @override
  List<Object?> get props => [conversations, messagesCache];
}

class ConversationsError extends ConversationsState {
  final String message;
  const ConversationsError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class ConversationsBloc extends Bloc<ConversationsEvent, ConversationsState> {
  final ConversationsRepository _repository;

  ConversationsBloc(this._repository) : super(const ConversationsInitial()) {
    on<LoadConversations>(_onLoadConversations);
    on<LoadMessages>(_onLoadMessages);
  }

  Future<void> _onLoadConversations(
    LoadConversations event,
    Emitter<ConversationsState> emit,
  ) async {
    emit(const ConversationsLoading());
    final result = await _repository.getConversations(event.deviceId);
    result.fold(
      (failure) => emit(ConversationsError(failure.message)),
      (conversations) => emit(ConversationsLoaded(conversations)),
    );
  }

  Future<void> _onLoadMessages(
    LoadMessages event,
    Emitter<ConversationsState> emit,
  ) async {
    final current = state;
    if (current is! ConversationsLoaded) return;

    // Already cached
    if (current.messagesCache.containsKey(event.conversationId)) return;

    final result = await _repository.getMessages(event.conversationId);
    result.fold(
      (_) => null,
      (messages) => emit(current.copyWithMessages(event.conversationId, messages)),
    );
  }
}
