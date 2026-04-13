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

  Future<void> deleteDevice(String id) async {
    await _client.delete('/devices/$id');
  }

  Future<Map<String, dynamic>> getStats(String id) async {
    final data = await _client.get('/devices/$id/stats');
    return data as Map<String, dynamic>;
  }

  /// Calls the backend to synthesize a short preview phrase with the given
  /// voice settings and returns the decoded MP3 bytes.
  Future<Uint8List> previewVoice(
    String id, {
    String? voicePreset,
    double? speed,
    double? stability,
  }) async {
    try {
      final response = await _client.dio.post(
        '/devices/$id/voice/preview',
        data: {
          'voice_preset': voicePreset,
          'voice_speed': speed,
          'voice_stability': stability,
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
}
