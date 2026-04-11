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

  Future<void> deleteDevice(String id) async {
    await _client.delete('/devices/$id');
  }

  Future<Map<String, dynamic>> getStats(String id) async {
    final data = await _client.get('/devices/$id/stats');
    return data as Map<String, dynamic>;
  }
}
