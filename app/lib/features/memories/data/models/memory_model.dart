import '../../domain/entities/memory_entity.dart';

class MemoryModel extends Memory {
  const MemoryModel({
    required super.id,
    required super.fact,
    required super.category,
    required super.confidence,
    required super.createdAt,
  });

  factory MemoryModel.fromJson(Map<String, dynamic> json) {
    return MemoryModel(
      id: json['id'] as String,
      fact: json['fact'] as String,
      category: json['category'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
