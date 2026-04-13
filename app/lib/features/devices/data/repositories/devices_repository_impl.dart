import 'dart:typed_data';

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
  Future<Either<Failure, Device>> claimByToken(String deviceToken) async {
    try {
      final device = await _datasource.claimByToken(deviceToken);
      return Right(device);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> requestProvision(String id) async {
    try {
      await _datasource.requestProvision(id);
      return const Right(null);
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

  @override
  Future<Either<Failure, Map<String, dynamic>>> getStats(String id) async {
    try {
      final stats = await _datasource.getStats(id);
      return Right(stats);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, bool>> pushVoicePreviewToDevice(
    String id, {
    String? voicePreset,
    double? speed,
    double? stability,
  }) async {
    try {
      final playing = await _datasource.pushVoicePreviewToDevice(
        id,
        voicePreset: voicePreset,
        speed: speed,
        stability: stability,
      );
      return Right(playing);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Uint8List>> previewVoice(
    String id, {
    String? voicePreset,
    double? speed,
    double? stability,
  }) async {
    try {
      final bytes = await _datasource.previewVoice(
        id,
        voicePreset: voicePreset,
        speed: speed,
        stability: stability,
      );
      return Right(bytes);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }
}
