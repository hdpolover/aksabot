import 'package:equatable/equatable.dart';

class Message extends Equatable {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  @override
  List<Object> get props => [id, role, content, createdAt];
}
