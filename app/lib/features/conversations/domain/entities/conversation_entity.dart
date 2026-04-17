import 'package:equatable/equatable.dart';

class Conversation extends Equatable {
  final String id;
  final String deviceId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? preview;
  final int messageCount;
  final bool guestMode;

  const Conversation({
    required this.id,
    required this.deviceId,
    required this.startedAt,
    this.endedAt,
    this.preview,
    this.messageCount = 0,
    this.guestMode = false,
  });

  Duration? get duration {
    if (endedAt == null) return null;
    return endedAt!.difference(startedAt);
  }

  @override
  List<Object?> get props => [
        id,
        deviceId,
        startedAt,
        endedAt,
        preview,
        messageCount,
        guestMode,
      ];
}
