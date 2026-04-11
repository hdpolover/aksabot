import '../../domain/entities/device_entity.dart';

class DeviceModel extends Device {
  const DeviceModel({
    required super.id,
    required super.name,
    super.lastSeenAt,
    super.settingsJson,
    super.personalityJson,
    super.firmwareVersion,
    super.wifiSsid,
    super.wifiRssi,
    super.deviceToken,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Unnamed Device',
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.parse(json['lastSeenAt'] as String)
          : null,
      settingsJson: (json['settingsJson'] as Map<String, dynamic>?) ?? {},
      personalityJson: (json['personalityJson'] as Map<String, dynamic>?) ?? {},
      firmwareVersion: json['firmwareVersion'] as String?,
      wifiSsid: json['wifiSsid'] as String?,
      wifiRssi: (json['wifiRssi'] as int?) ??
          (json['settingsJson'] is Map ? (json['settingsJson']['wifi_rssi'] as int?) : null),
      deviceToken: json['deviceToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
      'settingsJson': settingsJson,
      'personalityJson': personalityJson,
    };
  }
}
