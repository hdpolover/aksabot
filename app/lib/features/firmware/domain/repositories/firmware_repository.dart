import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/firmware_release.dart';
import '../entities/ota_status.dart';

abstract class FirmwareRepository {
  Future<Either<Failure, FirmwareRelease?>> getLatestRelease();
  Future<Either<Failure, Map<String, dynamic>>> triggerOta(
    String deviceId, {
    String? releaseId,
  });
  Future<Either<Failure, OtaStatus>> getOtaStatus(String deviceId);
}
