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

class VisionRepository {
  final Dio dio;

  const VisionRepository({required this.dio});

  Future<List<FaceProfileModel>> getProfiles() async {
    final response = await dio.get<List<dynamic>>('/vision/profiles');
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(FaceProfileModel.fromJson)
        .toList();
  }

  Future<FaceProfileModel> enrollFromFile({required File photo, required String name}) async {
    final formData = FormData.fromMap({
      'photos': await MultipartFile.fromFile(photo.path, filename: 'photo.jpg'),
      'name': name,
    });
    final response = await dio.post<Map<String, dynamic>>(
      '/vision/enroll',
      data: formData,
    );
    return FaceProfileModel.fromJson(response.data!);
  }

  Future<void> triggerDeskCapture({
    required String cameraDeviceId,
    required String name,
  }) async {
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
      '/devices/$deviceId',
      data: {
        'settingsJson': {'vision_mode': mode},
      },
    );
  }
}
