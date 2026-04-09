import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';
import '../datasources/devices_remote_datasource.dart';

class DevicesRepositoryImpl implements DevicesRepository {
  final DevicesRemoteDatasource _datasource;

  DevicesRepositoryImpl(this._datasource);

  @override
  Future<Either<Failure, List<Device>>> getDevices() async {
    try {
      final devices = await _datasource.getDevices();
      return Right(devices);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Device>> getDevice(String id) async {
    try {
      final device = await _datasource.getDevice(id);
      return Right(device);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Device>> createDevice({String? name}) async {
    try {
      final device = await _datasource.createDevice(name: name);
      return Right(device);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Device>> updateSettings(
    String id,
    Map<String, dynamic> settings,
  ) async {
    try {
      final device = await _datasource.updateSettings(id, settings);
      return Right(device);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getPersonality(String id) async {
    try {
      final personality = await _datasource.getPersonality(id);
      return Right(personality);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> updatePersonality(
    String id,
    Map<String, dynamic> personality,
  ) async {
    try {
      final updated = await _datasource.updatePersonality(id, personality);
      return Right(updated);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> deleteDevice(String id) async {
    try {
      await _datasource.deleteDevice(id);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }
}
