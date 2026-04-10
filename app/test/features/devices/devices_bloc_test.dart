import 'package:aksabot/features/devices/domain/entities/device_entity.dart';
import 'package:aksabot/features/devices/domain/repositories/devices_repository.dart';
import 'package:aksabot/features/devices/presentation/bloc/devices_bloc.dart';
import 'package:aksabot/core/error/failures.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDevicesRepository extends Mock implements DevicesRepository {}

void main() {
  late MockDevicesRepository mockRepository;

  // ---------------------------------------------------------------------------
  // Test fixtures
  // ---------------------------------------------------------------------------

  final tNow = DateTime(2026, 4, 10, 9, 0);

  final tDevice1 = Device(
    id: 'device-1',
    name: 'Aksabot Desk',
    lastSeenAt: tNow,
    settingsJson: const {'volume': 80},
    personalityJson: const {'tone': 'friendly'},
  );

  final tDevice2 = Device(
    id: 'device-2',
    name: 'Aksabot Lab',
    lastSeenAt: tNow.subtract(const Duration(hours: 2)),
  );

  final tDevices = [tDevice1, tDevice2];

  final tUpdatedDevice = Device(
    id: 'device-1',
    name: 'Aksabot Desk',
    lastSeenAt: tNow,
    settingsJson: const {'volume': 70},
    personalityJson: const {'tone': 'friendly'},
  );

  const tServerFailure = ServerFailure('Server error');

  setUp(() {
    mockRepository = MockDevicesRepository();
  });

  // ---------------------------------------------------------------------------
  // LoadDevices
  // ---------------------------------------------------------------------------

  group('LoadDevices', () {
    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesLoaded] on success',
      build: () {
        when(() => mockRepository.getDevices())
            .thenAnswer((_) async => Right(tDevices));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadDevices()),
      expect: () => [
        const DevicesLoading(),
        DevicesLoaded(tDevices),
      ],
      verify: (_) => verify(() => mockRepository.getDevices()).called(1),
    );

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesError] on failure',
      build: () {
        when(() => mockRepository.getDevices())
            .thenAnswer((_) async => const Left(tServerFailure));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadDevices()),
      expect: () => [
        const DevicesLoading(),
        const DevicesError('Server error'),
      ],
    );

    blocTest<DevicesBloc, DevicesState>(
      'emits DevicesLoaded with empty list when user has no devices',
      build: () {
        when(() => mockRepository.getDevices())
            .thenAnswer((_) async => const Right([]));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadDevices()),
      expect: () => [
        const DevicesLoading(),
        const DevicesLoaded([]),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // LoadDevice
  // ---------------------------------------------------------------------------

  group('LoadDevice', () {
    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DeviceDetailLoaded] on success',
      build: () {
        when(() => mockRepository.getDevice('device-1'))
            .thenAnswer((_) async => Right(tDevice1));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadDevice('device-1')),
      expect: () => [
        const DevicesLoading(),
        DeviceDetailLoaded(tDevice1),
      ],
      verify: (_) =>
          verify(() => mockRepository.getDevice('device-1')).called(1),
    );

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesError] when device not found',
      build: () {
        when(() => mockRepository.getDevice(any()))
            .thenAnswer((_) async =>
                const Left(ServerFailure('Device not found', statusCode: 404)));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const LoadDevice('missing-id')),
      expect: () => [
        const DevicesLoading(),
        const DevicesError('Device not found'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // CreateDevice
  // ---------------------------------------------------------------------------

  group('CreateDevice', () {
    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesLoaded] after creating then reloading',
      build: () {
        when(() => mockRepository.createDevice(name: 'New Bot'))
            .thenAnswer((_) async => Right(tDevice2));
        when(() => mockRepository.getDevices())
            .thenAnswer((_) async => Right(tDevices));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const CreateDevice(name: 'New Bot')),
      // The BLoC internally calls add(LoadDevices()) after a successful create.
      // bloc_test collapses the second DevicesLoading because the re-dispatched
      // event is processed before the outer act() frame completes — so the
      // state transitions are: Loading -> Loaded (no duplicate Loading visible).
      expect: () => [
        const DevicesLoading(),
        DevicesLoaded(tDevices),
      ],
      verify: (_) {
        verify(() => mockRepository.createDevice(name: 'New Bot')).called(1);
        verify(() => mockRepository.getDevices()).called(1);
      },
    );

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesError] when create fails',
      build: () {
        when(() => mockRepository.createDevice(name: any(named: 'name')))
            .thenAnswer((_) async => const Left(tServerFailure));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const CreateDevice(name: 'Bad Bot')),
      expect: () => [
        const DevicesLoading(),
        const DevicesError('Server error'),
      ],
    );

    blocTest<DevicesBloc, DevicesState>(
      'creates device without a name when name is omitted',
      build: () {
        when(() => mockRepository.createDevice(name: null))
            .thenAnswer((_) async => Right(tDevice1));
        when(() => mockRepository.getDevices())
            .thenAnswer((_) async => Right(tDevices));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const CreateDevice()),
      verify: (_) =>
          verify(() => mockRepository.createDevice(name: null)).called(1),
    );
  });

  // ---------------------------------------------------------------------------
  // DeleteDevice
  // ---------------------------------------------------------------------------

  group('DeleteDevice', () {
    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesLoaded] after deleting then reloading',
      build: () {
        when(() => mockRepository.deleteDevice('device-2'))
            .thenAnswer((_) async => const Right(null));
        when(() => mockRepository.getDevices())
            .thenAnswer((_) async => Right([tDevice1]));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const DeleteDevice('device-2')),
      // Same as CreateDevice: the internal add(LoadDevices()) collapses the
      // second DevicesLoading within the same bloc_test frame.
      expect: () => [
        const DevicesLoading(),
        DevicesLoaded([tDevice1]),
      ],
      verify: (_) {
        verify(() => mockRepository.deleteDevice('device-2')).called(1);
        verify(() => mockRepository.getDevices()).called(1);
      },
    );

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesError] when delete fails',
      build: () {
        when(() => mockRepository.deleteDevice(any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const DeleteDevice('device-1')),
      expect: () => [
        const DevicesLoading(),
        const DevicesError('Server error'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // UpdateSettings
  // ---------------------------------------------------------------------------

  group('UpdateSettings', () {
    final tSettingsPatch = {'volume': 70};

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DeviceDetailLoaded] with updated device on success',
      build: () {
        when(() =>
                mockRepository.updateSettings('device-1', tSettingsPatch))
            .thenAnswer((_) async => Right(tUpdatedDevice));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(UpdateSettings('device-1', tSettingsPatch)),
      expect: () => [
        const DevicesLoading(),
        DeviceDetailLoaded(tUpdatedDevice),
      ],
      verify: (_) => verify(
              () => mockRepository.updateSettings('device-1', tSettingsPatch))
          .called(1),
    );

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesError] when settings update fails',
      build: () {
        when(() => mockRepository.updateSettings(any(), any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(UpdateSettings('device-1', tSettingsPatch)),
      expect: () => [
        const DevicesLoading(),
        const DevicesError('Server error'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // UpdatePersonality
  // ---------------------------------------------------------------------------

  group('UpdatePersonality', () {
    final tPersonalityPatch = {'tone': 'sarcastic'};

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DeviceDetailLoaded] after updating then reloading device detail',
      build: () {
        when(() => mockRepository.updatePersonality(
                'device-1', tPersonalityPatch))
            .thenAnswer(
                (_) async => Right({'tone': 'sarcastic', 'energy': 'high'}));
        when(() => mockRepository.getDevice('device-1'))
            .thenAnswer((_) async => Right(tDevice1));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) =>
          bloc.add(UpdatePersonality('device-1', tPersonalityPatch)),
      // The BLoC internally calls add(LoadDevice(deviceId)) after a successful
      // personality update. bloc_test collapses the second DevicesLoading into
      // the same frame — only one Loading is visible before DeviceDetailLoaded.
      expect: () => [
        const DevicesLoading(),
        DeviceDetailLoaded(tDevice1),
      ],
      verify: (_) {
        verify(() =>
                mockRepository.updatePersonality('device-1', tPersonalityPatch))
            .called(1);
        verify(() => mockRepository.getDevice('device-1')).called(1);
      },
    );

    blocTest<DevicesBloc, DevicesState>(
      'emits [DevicesLoading, DevicesError] when updatePersonality fails',
      build: () {
        when(() => mockRepository.updatePersonality(any(), any()))
            .thenAnswer((_) async => const Left(tServerFailure));
        return DevicesBloc(mockRepository);
      },
      act: (bloc) =>
          bloc.add(UpdatePersonality('device-1', tPersonalityPatch)),
      expect: () => [
        const DevicesLoading(),
        const DevicesError('Server error'),
      ],
    );
  });
}
