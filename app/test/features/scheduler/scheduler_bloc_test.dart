import 'package:aksabot/features/scheduler/domain/entities/pomodoro_entity.dart';
import 'package:aksabot/features/scheduler/domain/entities/reminder_config_entity.dart';
import 'package:aksabot/features/scheduler/domain/repositories/scheduler_repository.dart';
import 'package:aksabot/features/scheduler/presentation/bloc/scheduler_bloc.dart';
import 'package:aksabot/core/error/failures.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSchedulerRepository extends Mock implements SchedulerRepository {}

void main() {
  late MockSchedulerRepository mockRepository;

  // ---------------------------------------------------------------------------
  // Test fixtures
  // ---------------------------------------------------------------------------

  const tReminderItem = ReminderItem(enabled: true, intervalMinutes: 60);
  const tDisabledItem = ReminderItem(enabled: false, intervalMinutes: 30);

  const tReminderConfig = ReminderConfig(
    standUp: tReminderItem,
    hydration: tReminderItem,
    eyeBreak: tDisabledItem,
    stretch: tReminderItem,
    posture: tDisabledItem,
  );

  const tUpdatedConfig = ReminderConfig(
    standUp: ReminderItem(enabled: true, intervalMinutes: 45),
    hydration: tReminderItem,
    eyeBreak: tDisabledItem,
    stretch: tReminderItem,
    posture: tDisabledItem,
  );

  const tPomodoroActive = PomodoroStatus(
    active: true,
    phase: 'work',
    cycle: 1,
    durationMinutes: 25,
  );

  const tPomodoroInactive = PomodoroStatus(active: false);

  const tServerFailure = ServerFailure('Scheduler error');
  const tDeviceId = 'device-1';

  setUp(() {
    mockRepository = MockSchedulerRepository();
  });

  // ---------------------------------------------------------------------------
  // LoadReminderConfig
  // ---------------------------------------------------------------------------

  group('LoadReminderConfig', () {
    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, ReminderConfigLoaded] on success',
      build: () {
        when(() => mockRepository.getReminderConfig(tDeviceId))
            .thenAnswer((_) async => const Right(tReminderConfig));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadReminderConfig(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const ReminderConfigLoaded(tReminderConfig),
      ],
      verify: (_) =>
          verify(() => mockRepository.getReminderConfig(tDeviceId)).called(1),
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, SchedulerError] on failure',
      build: () {
        when(() => mockRepository.getReminderConfig(any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadReminderConfig(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const SchedulerError('Scheduler error'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // UpdateReminderConfig
  // ---------------------------------------------------------------------------

  group('UpdateReminderConfig', () {
    final tConfigPatch = {'standUp': {'enabled': true, 'intervalMinutes': 45}};

    blocTest<SchedulerBloc, SchedulerState>(
      'emits isSaving=true then ReminderConfigLoaded with updated config on success',
      build: () {
        when(() => mockRepository.getReminderConfig(tDeviceId))
            .thenAnswer((_) async => const Right(tReminderConfig));
        when(() => mockRepository.updateReminderConfig(tDeviceId, tConfigPatch))
            .thenAnswer((_) async => const Right(tUpdatedConfig));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadReminderConfig(tDeviceId));
        await Future<void>.delayed(Duration.zero);
        bloc.add(UpdateReminderConfig(tDeviceId, tConfigPatch));
      },
      expect: () => [
        const SchedulerLoading(),
        const ReminderConfigLoaded(tReminderConfig),
        // isSaving=true while awaiting the update
        const ReminderConfigLoaded(tReminderConfig, isSaving: true),
        const ReminderConfigLoaded(tUpdatedConfig),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits SchedulerError when updateReminderConfig fails',
      build: () {
        when(() => mockRepository.getReminderConfig(tDeviceId))
            .thenAnswer((_) async => const Right(tReminderConfig));
        when(() => mockRepository.updateReminderConfig(any(), any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadReminderConfig(tDeviceId));
        await Future<void>.delayed(Duration.zero);
        bloc.add(UpdateReminderConfig(tDeviceId, tConfigPatch));
      },
      expect: () => [
        const SchedulerLoading(),
        const ReminderConfigLoaded(tReminderConfig),
        const ReminderConfigLoaded(tReminderConfig, isSaving: true),
        const SchedulerError('Scheduler error'),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'skips isSaving=true emit when current state is not ReminderConfigLoaded',
      build: () {
        // No LoadReminderConfig dispatched first — state is SchedulerInitial
        when(() => mockRepository.updateReminderConfig(any(), any()))
            .thenAnswer((_) async => const Right(tUpdatedConfig));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(UpdateReminderConfig(tDeviceId, tConfigPatch)),
      expect: () => [
        // No isSaving intermediate state — goes straight to success
        const ReminderConfigLoaded(tUpdatedConfig),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // LoadPomodoroStatus
  // ---------------------------------------------------------------------------

  group('LoadPomodoroStatus', () {
    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, PomodoroStatusLoaded] on success',
      build: () {
        when(() => mockRepository.getPomodoroStatus(tDeviceId))
            .thenAnswer((_) async => const Right(tPomodoroActive));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadPomodoroStatus(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const PomodoroStatusLoaded(tPomodoroActive),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, SchedulerError] on failure',
      build: () {
        when(() => mockRepository.getPomodoroStatus(any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadPomodoroStatus(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const SchedulerError('Scheduler error'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StartPomodoro
  // ---------------------------------------------------------------------------

  group('StartPomodoro', () {
    blocTest<SchedulerBloc, SchedulerState>(
      'emits isActing=true then PomodoroStatusLoaded with active status on success',
      build: () {
        when(() => mockRepository.getPomodoroStatus(tDeviceId))
            .thenAnswer((_) async => const Right(tPomodoroInactive));
        when(() => mockRepository.startPomodoro(tDeviceId))
            .thenAnswer((_) async => const Right(tPomodoroActive));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadPomodoroStatus(tDeviceId));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const StartPomodoro(tDeviceId));
      },
      expect: () => [
        const SchedulerLoading(),
        const PomodoroStatusLoaded(tPomodoroInactive),
        const PomodoroStatusLoaded(tPomodoroInactive, isActing: true),
        const PomodoroStatusLoaded(tPomodoroActive),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits SchedulerError when startPomodoro fails',
      build: () {
        when(() => mockRepository.getPomodoroStatus(tDeviceId))
            .thenAnswer((_) async => const Right(tPomodoroInactive));
        when(() => mockRepository.startPomodoro(any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadPomodoroStatus(tDeviceId));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const StartPomodoro(tDeviceId));
      },
      expect: () => [
        const SchedulerLoading(),
        const PomodoroStatusLoaded(tPomodoroInactive),
        const PomodoroStatusLoaded(tPomodoroInactive, isActing: true),
        const SchedulerError('Scheduler error'),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'skips isActing=true when state is not PomodoroStatusLoaded',
      build: () {
        when(() => mockRepository.startPomodoro(tDeviceId))
            .thenAnswer((_) async => const Right(tPomodoroActive));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const StartPomodoro(tDeviceId)),
      expect: () => [
        const PomodoroStatusLoaded(tPomodoroActive),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StopPomodoro
  // ---------------------------------------------------------------------------

  group('StopPomodoro', () {
    blocTest<SchedulerBloc, SchedulerState>(
      'emits isActing=true then PomodoroStatusLoaded(active: false) on success',
      build: () {
        when(() => mockRepository.getPomodoroStatus(tDeviceId))
            .thenAnswer((_) async => const Right(tPomodoroActive));
        when(() => mockRepository.stopPomodoro(tDeviceId))
            .thenAnswer((_) async => const Right(null));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadPomodoroStatus(tDeviceId));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const StopPomodoro(tDeviceId));
      },
      expect: () => [
        const SchedulerLoading(),
        const PomodoroStatusLoaded(tPomodoroActive),
        const PomodoroStatusLoaded(tPomodoroActive, isActing: true),
        const PomodoroStatusLoaded(tPomodoroInactive),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits SchedulerError when stopPomodoro fails',
      build: () {
        when(() => mockRepository.getPomodoroStatus(tDeviceId))
            .thenAnswer((_) async => const Right(tPomodoroActive));
        when(() => mockRepository.stopPomodoro(any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) async {
        bloc.add(const LoadPomodoroStatus(tDeviceId));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const StopPomodoro(tDeviceId));
      },
      expect: () => [
        const SchedulerLoading(),
        const PomodoroStatusLoaded(tPomodoroActive),
        const PomodoroStatusLoaded(tPomodoroActive, isActing: true),
        const SchedulerError('Scheduler error'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StartFocusMode
  // ---------------------------------------------------------------------------

  group('StartFocusMode', () {
    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, FocusModeActive] on success without duration',
      build: () {
        when(() => mockRepository.startFocusMode(tDeviceId,
                durationMinutes: null))
            .thenAnswer((_) async => const Right({'active': true}));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const StartFocusMode(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const FocusModeActive(),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, FocusModeActive] on success with duration',
      build: () {
        when(() => mockRepository.startFocusMode(tDeviceId,
                durationMinutes: 90))
            .thenAnswer((_) async => const Right({'active': true}));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) =>
          bloc.add(const StartFocusMode(tDeviceId, durationMinutes: 90)),
      expect: () => [
        const SchedulerLoading(),
        const FocusModeActive(),
      ],
      verify: (_) => verify(() => mockRepository.startFocusMode(tDeviceId,
          durationMinutes: 90)).called(1),
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, SchedulerError] on failure',
      build: () {
        when(() => mockRepository.startFocusMode(any(),
                durationMinutes: any(named: 'durationMinutes')))
            .thenAnswer((_) async => const Left(tServerFailure));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const StartFocusMode(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const SchedulerError('Scheduler error'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // StopFocusMode
  // ---------------------------------------------------------------------------

  group('StopFocusMode', () {
    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, FocusModeInactive] on success',
      build: () {
        when(() => mockRepository.stopFocusMode(tDeviceId))
            .thenAnswer((_) async => const Right(null));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const StopFocusMode(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const FocusModeInactive(),
      ],
      verify: (_) =>
          verify(() => mockRepository.stopFocusMode(tDeviceId)).called(1),
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'emits [SchedulerLoading, SchedulerError] on failure',
      build: () {
        when(() => mockRepository.stopFocusMode(any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return SchedulerBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const StopFocusMode(tDeviceId)),
      expect: () => [
        const SchedulerLoading(),
        const SchedulerError('Scheduler error'),
      ],
    );
  });
}
