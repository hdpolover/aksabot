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
}
