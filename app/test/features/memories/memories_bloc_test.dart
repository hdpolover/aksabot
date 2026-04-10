import 'package:aksabot/features/memories/domain/entities/memory_entity.dart';
import 'package:aksabot/features/memories/domain/repositories/memories_repository.dart';
import 'package:aksabot/features/memories/presentation/bloc/memories_bloc.dart';
import 'package:aksabot/core/error/failures.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemoriesRepository extends Mock implements MemoriesRepository {}

void main() {
  late MockMemoriesRepository mockRepository;

  // ---------------------------------------------------------------------------
  // Test fixtures
  // ---------------------------------------------------------------------------

  final tNow = DateTime(2026, 4, 10);

  final tMemories = [
    Memory(
      id: 'mem-1',
      fact: 'Hendra prefers dark mode',
      category: 'preferences',
      confidence: 0.9,
      createdAt: tNow,
    ),
    Memory(
      id: 'mem-2',
      fact: 'Hendra uses Flutter for mobile',
      category: 'skills',
      confidence: 0.8,
      createdAt: tNow,
    ),
  ];

  final tPreferenceMemories = [tMemories.first];

  final tUpdatedMemory = Memory(
    id: 'mem-1',
    fact: 'Hendra prefers dark mode and Tokyo Night theme',
    category: 'preferences',
    confidence: 0.9,
    createdAt: tNow,
  );

  const tServerFailure = ServerFailure('Server error');

  setUp(() {
    mockRepository = MockMemoriesRepository();
  });

  // ---------------------------------------------------------------------------
  // LoadMemories — without category filter
  // ---------------------------------------------------------------------------

  group('LoadMemories without filter', () {
    blocTest<MemoriesBloc, MemoriesState>(
      'emits [MemoriesLoading, MemoriesLoaded] with all memories on success',
      build: () {
        when(() => mockRepository.getMemories('device-1', category: null))
            .thenAnswer((_) async => Right(tMemories));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadMemories('device-1')),
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded(tMemories),
      ],
      verify: (_) =>
          verify(() => mockRepository.getMemories('device-1', category: null))
              .called(1),
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'emits [MemoriesLoading, MemoriesError] on failure',
      build: () {
        when(() => mockRepository.getMemories(any(), category: any(named: 'category')))
            .thenAnswer((_) async => const Left(tServerFailure));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadMemories('device-1')),
      expect: () => [
        const MemoriesLoading(),
        const MemoriesError('Server error'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // LoadMemories — with category filter
  // ---------------------------------------------------------------------------

  group('LoadMemories with category filter', () {
    blocTest<MemoriesBloc, MemoriesState>(
      'emits MemoriesLoaded with selectedCategory set when filter provided',
      build: () {
        when(() => mockRepository.getMemories('device-1',
                category: 'preferences'))
            .thenAnswer((_) async => Right(tPreferenceMemories));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) =>
          bloc.add(const LoadMemories('device-1', category: 'preferences')),
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded(tPreferenceMemories, selectedCategory: 'preferences'),
      ],
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'passes category to repository and preserves it in state',
      build: () {
        when(() =>
                mockRepository.getMemories('device-1', category: 'skills'))
            .thenAnswer((_) async => Right([tMemories[1]]));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) =>
          bloc.add(const LoadMemories('device-1', category: 'skills')),
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded([tMemories[1]], selectedCategory: 'skills'),
      ],
      verify: (_) => verify(
              () => mockRepository.getMemories('device-1', category: 'skills'))
          .called(1),
    );
  });

  // ---------------------------------------------------------------------------
  // DeleteMemory
  // ---------------------------------------------------------------------------

  group('DeleteMemory', () {
    blocTest<MemoriesBloc, MemoriesState>(
      'removes the deleted memory from loaded list on success',
      build: () {
        when(() => mockRepository.getMemories('device-1', category: null))
            .thenAnswer((_) async => Right(tMemories));
        when(() => mockRepository.deleteMemory('mem-1'))
            .thenAnswer((_) async => const Right(null));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadMemories('device-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const DeleteMemory('mem-1'));
      },
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded(tMemories),
        // Only mem-2 remains after deleting mem-1
        MemoriesLoaded([tMemories[1]]),
      ],
      verify: (_) =>
          verify(() => mockRepository.deleteMemory('mem-1')).called(1),
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'preserves selectedCategory when deleting a filtered memory',
      build: () {
        when(() => mockRepository.getMemories('device-1',
                category: 'preferences'))
            .thenAnswer((_) async => Right(tPreferenceMemories));
        when(() => mockRepository.deleteMemory('mem-1'))
            .thenAnswer((_) async => const Right(null));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadMemories('device-1', category: 'preferences'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const DeleteMemory('mem-1'));
      },
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded(tPreferenceMemories, selectedCategory: 'preferences'),
        MemoriesLoaded(const [], selectedCategory: 'preferences'),
      ],
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'does nothing when state is not MemoriesLoaded',
      build: () => MemoriesBloc(mockRepository),
      act: (bloc) => bloc.add(const DeleteMemory('mem-1')),
      expect: () => <MemoriesState>[],
      verify: (_) =>
          verifyNever(() => mockRepository.deleteMemory(any())),
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'does not emit new state when deleteMemory fails',
      build: () {
        when(() => mockRepository.getMemories('device-1', category: null))
            .thenAnswer((_) async => Right(tMemories));
        when(() => mockRepository.deleteMemory('mem-1'))
            .thenAnswer((_) async => const Left(tServerFailure));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadMemories('device-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const DeleteMemory('mem-1'));
      },
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded(tMemories),
        // No additional state — the BLoC folds Left to null on delete failure.
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // UpdateMemory
  // ---------------------------------------------------------------------------

  group('UpdateMemory', () {
    blocTest<MemoriesBloc, MemoriesState>(
      'reloads memories for the current device after a successful update',
      build: () {
        // First load
        when(() => mockRepository.getMemories('device-1', category: null))
            .thenAnswer((_) async => Right(tMemories));
        // Update call
        when(() => mockRepository.updateMemory('mem-1',
                fact: 'Hendra prefers dark mode and Tokyo Night theme',
                category: null))
            .thenAnswer((_) async => Right(tUpdatedMemory));
        // Reload after update (LoadMemories is re-dispatched internally)
        // The second call returns the refreshed list
        var callCount = 0;
        when(() => mockRepository.getMemories('device-1', category: null))
            .thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? Right(tMemories)
              : Right([tUpdatedMemory, tMemories[1]]);
        });
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadMemories('device-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const UpdateMemory('mem-1',
            fact: 'Hendra prefers dark mode and Tokyo Night theme'));
        // Allow internal LoadMemories re-dispatch to complete
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded(tMemories),
        // Re-dispatched LoadMemories emits Loading then Loaded again
        const MemoriesLoading(),
        MemoriesLoaded([tUpdatedMemory, tMemories[1]]),
      ],
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'does nothing when state is not MemoriesLoaded',
      build: () => MemoriesBloc(mockRepository),
      act: (bloc) =>
          bloc.add(const UpdateMemory('mem-1', fact: 'Updated fact')),
      expect: () => <MemoriesState>[],
      verify: (_) =>
          verifyNever(() => mockRepository.updateMemory(any())),
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'does nothing when _currentDeviceId is not set (no prior LoadMemories)',
      build: () => MemoriesBloc(mockRepository),
      // No LoadMemories dispatched — _currentDeviceId is null
      act: (bloc) =>
          bloc.add(const UpdateMemory('mem-1', fact: 'Updated fact')),
      expect: () => <MemoriesState>[],
    );

    blocTest<MemoriesBloc, MemoriesState>(
      'does not reload when updateMemory fails',
      build: () {
        when(() => mockRepository.getMemories('device-1', category: null))
            .thenAnswer((_) async => Right(tMemories));
        when(() => mockRepository.updateMemory('mem-1',
                fact: 'bad update', category: null))
            .thenAnswer((_) async => const Left(tServerFailure));
        return MemoriesBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadMemories('device-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const UpdateMemory('mem-1', fact: 'bad update'));
      },
      expect: () => [
        const MemoriesLoading(),
        MemoriesLoaded(tMemories),
        // No additional states — Left result folds to null, no reload triggered.
      ],
      verify: (_) {
        // getMemories was called exactly once (for the initial LoadMemories).
        // The updateMemory failure prevents the internal re-dispatch of
        // LoadMemories, so getMemories is NOT called a second time.
        verify(() => mockRepository.getMemories('device-1', category: null))
            .called(1);
        verify(() => mockRepository.updateMemory('mem-1',
            fact: 'bad update', category: null)).called(1);
      },
    );
  });
}
