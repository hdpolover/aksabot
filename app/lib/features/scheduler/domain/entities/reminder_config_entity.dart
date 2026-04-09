import 'package:equatable/equatable.dart';

class ReminderConfig extends Equatable {
  final ReminderItem standUp;
  final ReminderItem hydration;
  final ReminderItem eyeBreak;
  final ReminderItem stretch;
  final ReminderItem posture;

  const ReminderConfig({
    required this.standUp,
    required this.hydration,
    required this.eyeBreak,
    required this.stretch,
    required this.posture,
  });

  /// Returns all reminder items as a named list for iteration in UI.
  List<MapEntry<String, ReminderItem>> get entries => [
        MapEntry('Stand Up', standUp),
        MapEntry('Hydration', hydration),
        MapEntry('Eye Break', eyeBreak),
        MapEntry('Stretch', stretch),
        MapEntry('Posture', posture),
      ];

  @override
  List<Object> get props => [standUp, hydration, eyeBreak, stretch, posture];
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
