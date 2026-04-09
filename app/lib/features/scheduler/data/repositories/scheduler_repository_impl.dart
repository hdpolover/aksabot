import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/reminder_config_entity.dart';
import '../../domain/entities/pomodoro_entity.dart';
import '../../domain/repositories/scheduler_repository.dart';
import '../datasources/scheduler_remote_datasource.dart';

class SchedulerRepositoryImpl implements SchedulerRepository {
  final SchedulerRemoteDatasource _datasource;

  SchedulerRepositoryImpl(this._datasource);

  @override
  Future<Either<Failure, ReminderConfig>> getReminderConfig(
    String deviceId,
  ) async {
    try {
      final config = await _datasource.getReminderConfig(deviceId);
      return Right(config);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, ReminderConfig>> updateReminderConfig(
    String deviceId,
    Map<String, dynamic> config,
  ) async {
    try {
      final updated = await _datasource.updateReminderConfig(deviceId, config);
      return Right(updated);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, PomodoroStatus>> startPomodoro(
    String deviceId,
  ) async {
    try {
      final status = await _datasource.startPomodoro(deviceId);
      return Right(status);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, void>> stopPomodoro(String deviceId) async {
    try {
      await _datasource.stopPomodoro(deviceId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }

  @override
  Future<Either<Failure, PomodoroStatus>> getPomodoroStatus(
    String deviceId,
  ) async {
    try {
      final status = await _datasource.getPomodoroStatus(deviceId);
      return Right(status);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    }
  }
}
