import 'package:equatable/equatable.dart';

class Device extends Equatable {
  final String id;
  final String name;
  final DateTime? lastSeenAt;
  final Map<String, dynamic> settingsJson;
  final Map<String, dynamic> personalityJson;

  /// Only populated once, from the create-device API response.
  /// Used during provisioning to write the token to the ESP32.
  final String? deviceToken;

  const Device({
    required this.id,
    required this.name,
    this.lastSeenAt,
    this.settingsJson = const {},
    this.personalityJson = const {},
    this.deviceToken,
  });

  bool get isOnline {
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inMinutes < 5;
  }

  @override
  List<Object?> get props => [id, name, lastSeenAt, settingsJson, personalityJson, deviceToken];
}
