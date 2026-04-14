import 'package:equatable/equatable.dart';

class ReminderConfig extends Equatable {
  final ReminderItem standUp;
  final ReminderItem hydration;
  final ReminderItem eyeBreak;
  final ReminderItem stretch;
  final ReminderItem posture;
  final bool allDay;
  final int workHoursStart; // 0-23
  final int workHoursEnd;   // 0-23

  const ReminderConfig({
    required this.standUp,
    required this.hydration,
    required this.eyeBreak,
    required this.stretch,
    required this.posture,
    this.allDay = false,
    this.workHoursStart = 9,
    this.workHoursEnd = 18,
  });

  List<MapEntry<String, ReminderItem>> get entries => [
        MapEntry('Stand Up', standUp),
        MapEntry('Hydration', hydration),
        MapEntry('Eye Break', eyeBreak),
        MapEntry('Stretch', stretch),
        MapEntry('Posture', posture),
      ];

  @override
  List<Object> get props =>
      [standUp, hydration, eyeBreak, stretch, posture, allDay, workHoursStart, workHoursEnd];
}

class ReminderItem extends Equatable {
  final bool enabled;
  final int intervalMinutes;

  const ReminderItem({
    required this.enabled,
    required this.intervalMinutes,
  });

  @override
  List<Object> get props => [enabled, intervalMinutes];
}
