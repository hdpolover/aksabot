import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/device_model.dart';

class DevicesRemoteDatasource {
  final ApiClient _client;

  DevicesRemoteDatasource(this._client);

  Future<List<DeviceModel>> getDevices() async {
    final data = await _client.get('/devices');
    final list = data as List;
    return list
        .map((json) => DeviceModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<DeviceModel> getDevice(String id) async {
    final data = await _client.get('/devices/$id');
    return DeviceModel.fromJson(data as Map<String, dynamic>);
  }

  /// Returns the device with deviceToken (shown only once, for provisioning).
  Future<DeviceModel> createDevice({String? name}) async {
    final data = await _client.post('/devices', data: {
      if (name != null) 'name': name, // ignore: use_null_aware_elements
    });
    final deviceJson = data['device'] as Map<String, dynamic>;
    final deviceToken = data['deviceToken'] as String?;
    if (deviceToken != null) {
      deviceJson['deviceToken'] = deviceToken;
    }
    return DeviceModel.fromJson(deviceJson);
  }

  Future<DeviceModel> updateSettings(
    String id,
    Map<String, dynamic> settings,
  ) async {
    final data = await _client.patch('/devices/$id/settings', data: settings);
    return DeviceModel.fromJson(data as Map<String, dynamic>);
  }

  Future<DeviceModel> claimByToken(String deviceToken) async {
    final data = await _client.post(
      '/devices/claim',
      data: {'deviceToken': deviceToken},
    );
    return DeviceModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> requestProvision(String id) async {
    await _client.post('/devices/$id/provision', data: {});
  }

  Future<void> reportPresence(
    String id,
    String event, {
    int awayDurationSeconds = 0,
  }) async {
    await _client.post('/devices/$id/presence', data: {
      'event': event,
      'awayDurationSeconds': awayDurationSeconds,
    });
  }

  Future<void> deleteDevice(String id) async {
    await _client.delete('/devices/$id');
  }

  Future<void> factoryReset(String id) async {
    await _client.post('/devices/$id/factory-reset', data: {});
  }

  Future<Map<String, dynamic>> getStats(String id) async {
    final data = await _client.get('/devices/$id/stats');
    return data as Map<String, dynamic>;
  }

  /// Tells the backend to synthesize the preview phrase and stream it to the
  /// device over WebSocket.  Returns true if the device accepted playback.
  Future<bool> pushVoicePreviewToDevice(
    String id, {
    String? language,
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  }) async {
    try {
      final response = await _client.dio.post(
        '/devices/$id/voice/preview/push',
        data: {
          'language': language,
          'voice_preset': voicePreset,
          'voice_speed': speed,
          'voice_stability': stability,
          'text': text,
        }..removeWhere((_, v) => v == null),
        options: Options(responseType: ResponseType.json),
      );
      final body = response.data as Map<String, dynamic>;
      final payload = body['data'] as Map<String, dynamic>;
      return payload['playing'] as bool? ?? false;
    } on DioException catch (e) {
      final data = e.response?.data;
      String message = 'Push preview failed';
      if (data is Map) {
        final msg = data['message'];
        if (msg is String) message = msg;
      }
      throw ServerException(message, statusCode: e.response?.statusCode);
    }
  }

  /// Calls the backend to synthesize a short preview phrase with the given
  /// voice settings and returns the decoded MP3 bytes.
  Future<Uint8List> previewVoice(
    String id, {
    String? language,
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  }) async {
    try {
      final response = await _client.dio.post(
        '/devices/$id/voice/preview',
        data: {
          'language': language,
          'voice_preset': voicePreset,
          'voice_speed': speed,
          'voice_stability': stability,
          'text': text,
        }..removeWhere((_, v) => v == null),
        options: Options(responseType: ResponseType.json),
      );

      // Response is wrapped in { data: { audio: base64, mimeType: 'audio/mpeg' } }
      final body = response.data as Map<String, dynamic>;
      final payload = body['data'] as Map<String, dynamic>;
      final base64Audio = payload['audio'] as String;
      return base64Decode(base64Audio);
    } on DioException catch (e) {
      final data = e.response?.data;
      String message = 'Preview failed';
      if (data is Map) {
        final msg = data['message'];
        if (msg is String) message = msg;
      }
      throw ServerException(message, statusCode: e.response?.statusCode);
    }
  }

  /// Upload a compressed JPEG image to the backend and push it to the device.
  Future<void> pushImage(
    String id,
    Uint8List imageBytes, {
    int durationMs = 10000,
  }) async {
    try {
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(imageBytes, filename: 'image.jpg'),
        'durationMs': durationMs.toString(),
      });
      await _client.dio.post('/devices/$id/push-image', data: formData);
    } on DioException catch (e) {
      final data = e.response?.data;
      String message = 'Image push failed';
      if (data is Map) {
        final msg = data['message'];
        if (msg is String) message = msg;
      }
      throw ServerException(message, statusCode: e.response?.statusCode);
    }
  }
}
