import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:aksabot/features/devices/data/repositories/vision_repository.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late VisionRepository repository;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    repository = VisionRepository(dio: mockDio);
  });

  group('getProfiles', () {
    test('returns list of profiles on success', () async {
      when(() => mockDio.get<List<dynamic>>('/vision/profiles')).thenAnswer(
        (_) async => Response(
          data: [
            {'id': 'fp1', 'name': 'Hendra', 'thumbnailUrl': null, 'createdAt': '2026-01-01T00:00:00.000Z'}
          ],
          statusCode: 200,
          requestOptions: RequestOptions(path: '/vision/profiles'),
        ),
      );
      final result = await repository.getProfiles();
      expect(result, hasLength(1));
      expect(result.first.name, 'Hendra');
    });
  });

  group('deleteProfile', () {
    test('calls DELETE endpoint', () async {
      when(() => mockDio.delete<dynamic>('/vision/profiles/fp1')).thenAnswer(
        (_) async => Response(
          statusCode: 204,
          requestOptions: RequestOptions(path: '/vision/profiles/fp1'),
        ),
      );
      await repository.deleteProfile('fp1');
      verify(() => mockDio.delete<dynamic>('/vision/profiles/fp1')).called(1);
    });
  });

  group('triggerDeskCapture', () {
    test('calls POST enroll/capture with deviceId and name', () async {
      when(() => mockDio.post<dynamic>(
            '/vision/enroll/capture',
            queryParameters: {'deviceId': 'cam-device-id'},
            data: {'name': 'Hendra'},
          )).thenAnswer(
        (_) async => Response(
          data: {'ok': true},
          statusCode: 201,
          requestOptions: RequestOptions(path: '/vision/enroll/capture'),
        ),
      );
      await repository.triggerDeskCapture(cameraDeviceId: 'cam-device-id', name: 'Hendra');
      verify(() => mockDio.post<dynamic>(
            '/vision/enroll/capture',
            queryParameters: {'deviceId': 'cam-device-id'},
            data: {'name': 'Hendra'},
          )).called(1);
    });
  });
}
