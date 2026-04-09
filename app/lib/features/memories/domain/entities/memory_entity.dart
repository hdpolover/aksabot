import 'package:equatable/equatable.dart';

class Memory extends Equatable {
  final String id;
  final String fact;
  final String category;
  final double confidence;
  final DateTime createdAt;

  const Memory({
    required this.id,
    required this.fact,
    required this.category,
    required this.confidence,
    required this.createdAt,
  });

  @override
  List<Object> get props => [id, fact, category, confidence, createdAt];
}
