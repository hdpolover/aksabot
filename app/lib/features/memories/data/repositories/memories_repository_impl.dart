import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/memory_entity.dart';
import '../../domain/repositories/memories_repository.dart';
import '../datasources/memories_remote_datasource.dart';

class MemoriesRepositoryImpl implements MemoriesRepository {
  final MemoriesRemoteDatasource _datasource;

  MemoriesRepositoryImpl(this._datasource);

  @override
  Future<Either<Failure, List<Memory>>> getMemories(
    String deviceId, {
    String? category,
  }) async {
    try {
      final memories = await _datasource.getMemories(
        deviceId,
        category: category,
      );
      return Right(memories);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Memory>> updateMemory(
    String id, {
    String? fact,
    String? category,
  }) async {
    try {
      final memory = await _datasource.updateMemory(
        id,
        fact: fact,
        category: category,
      );
      return Right(memory);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> deleteMemory(String id) async {
    try {
      await _datasource.deleteMemory(id);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }
}
