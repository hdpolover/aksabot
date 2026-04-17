import '../../domain/entities/conversation_entity.dart';

class ConversationModel extends Conversation {
  const ConversationModel({
    required super.id,
    required super.deviceId,
    required super.startedAt,
    super.endedAt,
    super.preview,
    super.messageCount,
    super.guestMode,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] != null
          ? DateTime.parse(json['endedAt'] as String)
          : null,
      preview: json['preview'] as String?,
      messageCount: (json['messageCount'] as int?) ?? 0,
      guestMode: (json['guestMode'] as bool?) ?? false,
    );
  }
}
