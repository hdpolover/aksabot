import 'package:equatable/equatable.dart';

class Device extends Equatable {
  final String id;
  final String name;
  final DateTime? lastSeenAt;
  final Map<String, dynamic> settingsJson;
  final Map<String, dynamic> personalityJson;

  const Device({
    required this.id,
    required this.name,
    this.lastSeenAt,
    this.settingsJson = const {},
    this.personalityJson = const {},
  });

  bool get isOnline {
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inMinutes < 5;
  }

  @override
  List<Object?> get props => [id, name, lastSeenAt, settingsJson, personalityJson];
}
