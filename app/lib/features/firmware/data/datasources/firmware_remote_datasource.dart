import '../../../../core/network/api_client.dart';
import '../models/firmware_release_model.dart';

class FirmwareRemoteDatasource {
  final ApiClient _client;

  FirmwareRemoteDatasource(this._client);

  Future<FirmwareReleaseModel?> getLatestRelease() async {
    try {
      final data = await _client.get('/firmware/latest');
      return FirmwareReleaseModel.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      // 404 means no releases uploaded yet — not an error
      return null;
    }
  }

  Future<Map<String, dynamic>> triggerOta(
    String deviceId, {
    String? releaseId,
  }) async {
    final data = await _client.post(
      '/devices/$deviceId/ota/trigger',
      data: {
        'releaseId': releaseId,
      },
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOtaStatus(String deviceId) async {
    final data = await _client.get('/devices/$deviceId/ota/status');
    return data as Map<String, dynamic>;
  }
}
