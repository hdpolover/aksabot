import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/memory_entity.dart';

abstract class MemoriesRepository {
  Future<Either<Failure, List<Memory>>> getMemories(
    String deviceId, {
    String? category,
  });

  Future<Either<Failure, Memory>> updateMemory(
    String id, {
    String? fact,
    String? category,
  });

  Future<Either<Failure, void>> deleteMemory(String id);
  Future<Either<Failure, Map<String, dynamic>>> scanMemories(String deviceId);
}
