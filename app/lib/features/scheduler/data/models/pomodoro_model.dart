import '../../domain/entities/pomodoro_entity.dart';

class PomodoroModel extends PomodoroStatus {
  const PomodoroModel({
    required super.active,
    super.phase,
    super.cycle,
    super.durationMinutes,
  });

  factory PomodoroModel.fromJson(Map<String, dynamic> json) {
    return PomodoroModel(
      active: json['active'] as bool,
      phase: json['phase'] as String?,
      cycle: json['cycle'] as int?,
      durationMinutes: json['durationMinutes'] as int?,
    );
  }
}
