import '../../domain/entities/device_entity.dart';

class DeviceModel extends Device {
  const DeviceModel({
    required super.id,
    required super.name,
    super.lastSeenAt,
    super.settingsJson,
    super.personalityJson,
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
