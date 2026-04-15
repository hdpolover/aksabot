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
  Future<Either<Failure, void>> reportPresence(
    String id,
    String event, {
    int awayDurationSeconds = 0,
  }) async {
    try {
      await _datasource.reportPresence(id, event,
          awayDurationSeconds: awayDurationSeconds);
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
  Future<Either<Failure, void>> factoryReset(String id) async {
    try {
      await _datasource.factoryReset(id);
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
    String? language,
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  }) async {
    try {
      final playing = await _datasource.pushVoicePreviewToDevice(
        id,
        language: language,
        voicePreset: voicePreset,
        speed: speed,
        stability: stability,
        text: text,
      );
      return Right(playing);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, Uint8List>> previewVoice(
    String id, {
    String? language,
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  }) async {
    try {
      final bytes = await _datasource.previewVoice(
        id,
        language: language,
        voicePreset: voicePreset,
        speed: speed,
        stability: stability,
        text: text,
      );
      return Right(bytes);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, bool>> sendVoiceMessage(String id, Uint8List audioBytes) async {
    try {
      final playing = await _datasource.sendVoiceMessage(id, audioBytes);
      return Right(playing);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> pushImage(
    String id,
    Uint8List imageBytes, {
    int durationMs = 10000,
  }) async {
    try {
      await _datasource.pushImage(id, imageBytes, durationMs: durationMs);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, VoiceInputResult>> sendVoiceInput(
    String id,
    Uint8List audioBytes, {
    String replyTarget = 'device',
  }) async {
    try {
      final data = await _datasource.sendVoiceInput(
        id,
        audioBytes,
        replyTarget: replyTarget,
      );
      return Right(VoiceInputResult.fromJson(data));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, DeviceLogs>> fetchLogs(String id) async {
    try {
      final data = await _datasource.fetchLogs(id);
      return Right(DeviceLogs.fromJson(data));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> sleepDevice(String id) async {
    try {
      await _datasource.sleepDevice(id);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> restartDevice(String id) async {
    try {
      await _datasource.restartDevice(id);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }
}
