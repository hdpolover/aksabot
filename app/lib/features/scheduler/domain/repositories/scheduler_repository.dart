import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/reminder_config_entity.dart';
import '../entities/pomodoro_entity.dart';

abstract class SchedulerRepository {
  Future<Either<Failure, ReminderConfig>> getReminderConfig(String deviceId);

  Future<Either<Failure, ReminderConfig>> updateReminderConfig(
    String deviceId,
    Map<String, dynamic> config,
  );

  Future<Either<Failure, PomodoroStatus>> startPomodoro(String deviceId);

  Future<Either<Failure, void>> stopPomodoro(String deviceId);

  Future<Either<Failure, PomodoroStatus>> getPomodoroStatus(String deviceId);

  // Focus mode
  Future<Either<Failure, Map<String, dynamic>>> startFocusMode(
    String deviceId, {
    int? durationMinutes,
  });
  Future<Either<Failure, void>> stopFocusMode(String deviceId);

  // Response pool
  Future<Either<Failure, Map<String, dynamic>>> refillPool(String deviceId);
  Future<Either<Failure, List<Map<String, dynamic>>>> getPoolStats(String deviceId);
}
