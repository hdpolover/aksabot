import 'dart:io';
import 'package:dio/dio.dart';

class FaceProfileModel {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final DateTime createdAt;

  const FaceProfileModel({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory FaceProfileModel.fromJson(Map<String, dynamic> json) => FaceProfileModel(
        id: json['id'] as String,
        name: json['name'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// Unwrap {"data": ...} wrapper that the backend puts on all responses
dynamic _unwrap(dynamic body) =>
    (body is Map<String, dynamic> && body.containsKey('data')) ? body['data'] : body;

class VisionRepository {
  final Dio dio;

  const VisionRepository({required this.dio});

  Future<List<FaceProfileModel>> getProfiles() async {
    final response = await dio.get('/vision/profiles');
    final list = _unwrap(response.data) as List<dynamic>;
    return list.cast<Map<String, dynamic>>().map(FaceProfileModel.fromJson).toList();
  }

  Future<FaceProfileModel> enrollFromFile({required File photo, required String name}) =>
      enrollFromFiles(photos: [photo], name: name);

  Future<FaceProfileModel> enrollFromFiles({required List<File> photos, required String name}) async {
    final parts = await Future.wait(
      photos.asMap().entries.map((e) =>
          MultipartFile.fromFile(e.value.path, filename: 'photo${e.key}.jpg')),
    );
    final formData = FormData.fromMap({'photos': parts, 'name': name});
    final response = await dio.post('/vision/enroll', data: formData);
    return FaceProfileModel.fromJson(_unwrap(response.data) as Map<String, dynamic>);
  }

  Future<void> triggerDeskCapture({required String cameraDeviceId, required String name}) async {
    await dio.post(
      '/vision/enroll/capture',
      queryParameters: {'deviceId': cameraDeviceId},
      data: {'name': name},
    );
  }

  Future<void> deleteProfile(String profileId) async {
    await dio.delete('/vision/profiles/$profileId');
  }

  Future<void> setVisionMode({required String deviceId, required String mode}) async {
    await dio.patch(
      '/devices/$deviceId/settings',
      data: {'vision_mode': mode},
    );
  }
}
