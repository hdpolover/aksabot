import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/firmware_release.dart';
import '../../domain/entities/ota_status.dart';
import '../../domain/repositories/firmware_repository.dart';
import '../datasources/firmware_remote_datasource.dart';

class FirmwareRepositoryImpl implements FirmwareRepository {
  final FirmwareRemoteDatasource _datasource;

  FirmwareRepositoryImpl(this._datasource);

  @override
  Future<Either<Failure, FirmwareRelease?>> getLatestRelease() async {
    try {
      final release = await _datasource.getLatestRelease();
      return Right(release);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> triggerOta(
    String deviceId, {
    String? releaseId,
  }) async {
    try {
      final result = await _datasource.triggerOta(deviceId, releaseId: releaseId);
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, OtaStatus>> getOtaStatus(String deviceId) async {
    try {
      final json = await _datasource.getOtaStatus(deviceId);
      return Right(OtaStatus.fromJson(json));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }
}
