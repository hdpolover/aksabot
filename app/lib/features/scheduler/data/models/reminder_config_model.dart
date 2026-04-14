import '../../domain/entities/reminder_config_entity.dart';

class ReminderConfigModel extends ReminderConfig {
  const ReminderConfigModel({
    required super.standUp,
    required super.hydration,
    required super.eyeBreak,
    required super.stretch,
    required super.posture,
    super.allDay,
    super.workHoursStart,
    super.workHoursEnd,
  });

  factory ReminderConfigModel.fromJson(Map<String, dynamic> json) {
    return ReminderConfigModel(
      standUp:   _parseItem(json['standUp']   as Map<String, dynamic>),
      hydration: _parseItem(json['hydration'] as Map<String, dynamic>),
      eyeBreak:  _parseItem(json['eyeBreak']  as Map<String, dynamic>),
      stretch:   _parseItem(json['stretch']   as Map<String, dynamic>),
      posture:   _parseItem(json['posture']   as Map<String, dynamic>),
      allDay:         json['allDay']         as bool? ?? false,
      workHoursStart: json['workHoursStart'] as int?  ?? 9,
      workHoursEnd:   json['workHoursEnd']   as int?  ?? 18,
    );
  }

  static ReminderItem _parseItem(Map<String, dynamic> json) {
    return ReminderItem(
      enabled:         json['enabled']         as bool,
      intervalMinutes: json['intervalMinutes'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'standUp':        _itemToJson(standUp),
      'hydration':      _itemToJson(hydration),
      'eyeBreak':       _itemToJson(eyeBreak),
      'stretch':        _itemToJson(stretch),
      'posture':        _itemToJson(posture),
      'allDay':         allDay,
      'workHoursStart': workHoursStart,
      'workHoursEnd':   workHoursEnd,
    };
  }

  static Map<String, dynamic> _itemToJson(ReminderItem item) {
    return {
      'enabled':         item.enabled,
      'intervalMinutes': item.intervalMinutes,
    };
  }
}
