import 'package:equatable/equatable.dart';

class PomodoroStatus extends Equatable {
  final bool active;
  final String? phase;
  final int? cycle;
  final int? durationMinutes;

  const PomodoroStatus({
    required this.active,
    this.phase,
    this.cycle,
    this.durationMinutes,
  });

  @override
  List<Object?> get props => [active, phase, cycle, durationMinutes];
}
