import 'package:aksabot/features/conversations/domain/entities/conversation_entity.dart';
import 'package:aksabot/features/conversations/domain/entities/message_entity.dart';
import 'package:aksabot/features/conversations/domain/repositories/conversations_repository.dart';
import 'package:aksabot/features/conversations/presentation/bloc/conversations_bloc.dart';
import 'package:aksabot/core/error/failures.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockConversationsRepository extends Mock
    implements ConversationsRepository {}

void main() {
  late MockConversationsRepository mockRepository;

  // ---------------------------------------------------------------------------
  // Test fixtures
  // ---------------------------------------------------------------------------

  final tNow = DateTime(2026, 4, 10, 9, 0);

  final tConversations = [
    Conversation(
      id: 'conv-1',
      deviceId: 'device-1',
      startedAt: tNow,
      endedAt: tNow.add(const Duration(minutes: 5)),
    ),
    Conversation(
      id: 'conv-2',
      deviceId: 'device-1',
      startedAt: tNow.add(const Duration(hours: 1)),
    ),
  ];

  final tMessages = [
    Message(
      id: 'msg-1',
      role: 'user',
      content: 'Hello Aksabot!',
      createdAt: tNow,
    ),
    Message(
      id: 'msg-2',
      role: 'assistant',
      content: 'Hey Hendra, good morning!',
      createdAt: tNow.add(const Duration(seconds: 2)),
    ),
  ];

  const tServerFailure = ServerFailure('Failed to load conversations');

  setUp(() {
    mockRepository = MockConversationsRepository();
  });

  // ---------------------------------------------------------------------------
  // LoadConversations
  // ---------------------------------------------------------------------------

  group('LoadConversations', () {
    blocTest<ConversationsBloc, ConversationsState>(
      'emits [ConversationsLoading, ConversationsLoaded] on success',
      build: () {
        when(() => mockRepository.getConversations('device-1'))
            .thenAnswer((_) async => Right(tConversations));
        return ConversationsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadConversations('device-1')),
      expect: () => [
        const ConversationsLoading(),
        ConversationsLoaded(tConversations),
      ],
      verify: (_) =>
          verify(() => mockRepository.getConversations('device-1')).called(1),
    );

    blocTest<ConversationsBloc, ConversationsState>(
      'emits [ConversationsLoading, ConversationsError] on failure',
      build: () {
        when(() => mockRepository.getConversations(any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return ConversationsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadConversations('device-1')),
      expect: () => [
        const ConversationsLoading(),
        const ConversationsError('Failed to load conversations'),
      ],
    );

    blocTest<ConversationsBloc, ConversationsState>(
      'emits [ConversationsLoading, ConversationsLoaded] with empty list when device has no conversations',
      build: () {
        when(() => mockRepository.getConversations('device-new'))
            .thenAnswer((_) async => const Right([]));
        return ConversationsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadConversations('device-new')),
      expect: () => [
        const ConversationsLoading(),
        const ConversationsLoaded([]),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // LoadMessages
  // ---------------------------------------------------------------------------

  group('LoadMessages', () {
    blocTest<ConversationsBloc, ConversationsState>(
      'emits updated ConversationsLoaded with messages when not cached',
      build: () {
        when(() => mockRepository.getConversations('device-1'))
            .thenAnswer((_) async => Right(tConversations));
        when(() => mockRepository.getMessages('conv-1'))
            .thenAnswer((_) async => Right(tMessages));
        return ConversationsBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadConversations('device-1'));
        // Wait for conversations to be loaded before requesting messages
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoadMessages('conv-1'));
      },
      expect: () => [
        const ConversationsLoading(),
        ConversationsLoaded(tConversations),
        ConversationsLoaded(tConversations,
            messagesCache: {'conv-1': tMessages}),
      ],
      verify: (_) =>
          verify(() => mockRepository.getMessages('conv-1')).called(1),
    );

    blocTest<ConversationsBloc, ConversationsState>(
      'does NOT re-fetch messages when already cached for that conversation',
      build: () {
        when(() => mockRepository.getConversations('device-1'))
            .thenAnswer((_) async => Right(tConversations));
        when(() => mockRepository.getMessages('conv-1'))
            .thenAnswer((_) async => Right(tMessages));
        return ConversationsBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadConversations('device-1'));
        await Future<void>.delayed(Duration.zero);
        // First fetch — populates cache
        bloc.add(const LoadMessages('conv-1'));
        await Future<void>.delayed(Duration.zero);
        // Second add — should be a no-op (already cached)
        bloc.add(const LoadMessages('conv-1'));
      },
      verify: (_) =>
          // getMessages must only be called once even though the event fires twice
          verify(() => mockRepository.getMessages('conv-1')).called(1),
    );

    blocTest<ConversationsBloc, ConversationsState>(
      'does nothing when state is not ConversationsLoaded',
      build: () {
        // No conversations loaded — bloc is in ConversationsInitial
        return ConversationsBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadMessages('conv-1')),
      expect: () => <ConversationsState>[],
      verify: (_) =>
          verifyNever(() => mockRepository.getMessages(any())),
    );

    blocTest<ConversationsBloc, ConversationsState>(
      'does not emit new state when getMessages returns a failure',
      build: () {
        when(() => mockRepository.getConversations('device-1'))
            .thenAnswer((_) async => Right(tConversations));
        when(() => mockRepository.getMessages('conv-1')).thenAnswer(
            (_) async => const Left(ServerFailure('Messages unavailable')));
        return ConversationsBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadConversations('device-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoadMessages('conv-1'));
      },
      expect: () => [
        const ConversationsLoading(),
        ConversationsLoaded(tConversations),
        // No additional state after the failed message load — the BLoC folds
        // Left to null and emits nothing.
      ],
    );
  });
}
