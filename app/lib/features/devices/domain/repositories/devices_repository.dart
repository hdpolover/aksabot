import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/device_entity.dart';

abstract class DevicesRepository {
  Future<Either<Failure, List<Device>>> getDevices();
  Future<Either<Failure, Device>> getDevice(String id);
  Future<Either<Failure, Device>> createDevice({String? name});
  Future<Either<Failure, Device>> updateSettings(String id, Map<String, dynamic> settings);
  Future<Either<Failure, Device>> claimByToken(String deviceToken);
  Future<Either<Failure, void>> requestProvision(String id);
  Future<Either<Failure, void>> reportPresence(
    String id,
    String event, {
    int awayDurationSeconds = 0,
  });
  Future<Either<Failure, void>> deleteDevice(String id);
  Future<Either<Failure, Map<String, dynamic>>> getStats(String id);
  Future<Either<Failure, bool>> pushVoicePreviewToDevice(
    String id, {
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  });

  Future<Either<Failure, Uint8List>> previewVoice(
    String id, {
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  });
}
