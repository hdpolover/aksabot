import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aksabot/features/devices/presentation/bloc/vision_bloc.dart';
import 'package:aksabot/features/devices/presentation/bloc/vision_event.dart';
import 'package:aksabot/features/devices/presentation/bloc/vision_state.dart';
import 'package:aksabot/features/devices/data/repositories/vision_repository.dart';

class MockVisionRepository extends Mock implements VisionRepository {}

final tProfile = FaceProfileModel(
  id: 'fp1',
  name: 'Hendra',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late MockVisionRepository mockRepo;

  setUp(() {
    mockRepo = MockVisionRepository();
  });

  group('LoadProfiles', () {
    blocTest<VisionBloc, VisionState>(
      'emits [VisionLoading, VisionLoaded] on success',
      build: () {
        when(() => mockRepo.getProfiles()).thenAnswer((_) async => [tProfile]);
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const LoadProfiles()),
      expect: () => [
        isA<VisionLoading>(),
        isA<VisionLoaded>().having((s) => s.profiles, 'profiles', hasLength(1)),
      ],
    );

    blocTest<VisionBloc, VisionState>(
      'emits [VisionLoading, VisionError] on failure',
      build: () {
        when(() => mockRepo.getProfiles()).thenThrow(Exception('network error'));
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const LoadProfiles()),
      expect: () => [isA<VisionLoading>(), isA<VisionError>()],
    );
  });

  group('DeleteProfile', () {
    blocTest<VisionBloc, VisionState>(
      'reloads profiles after delete',
      build: () {
        when(() => mockRepo.deleteProfile('fp1')).thenAnswer((_) async {});
        when(() => mockRepo.getProfiles()).thenAnswer((_) async => []);
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const DeleteProfile(profileId: 'fp1')),
      expect: () => [
        isA<VisionLoading>(),
        isA<VisionLoaded>().having((s) => s.profiles, 'profiles', isEmpty),
      ],
    );
  });

  group('ToggleVisionMode', () {
    blocTest<VisionBloc, VisionState>(
      'updates mode and reloads',
      build: () {
        when(() => mockRepo.setVisionMode(deviceId: 'dev1', mode: 'always'))
            .thenAnswer((_) async {});
        when(() => mockRepo.getProfiles()).thenAnswer((_) async => [tProfile]);
        return VisionBloc(repository: mockRepo);
      },
      act: (bloc) => bloc.add(const ToggleVisionMode(deviceId: 'dev1', mode: 'always')),
      expect: () => [
        isA<VisionLoading>(),
        isA<VisionLoaded>(),
      ],
    );
  });
}
