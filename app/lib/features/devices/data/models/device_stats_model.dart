class DeviceStats {
  final int conversationsToday;
  final int totalConversations;
  final int totalMemories;
  final int poolSize;
  final int? batteryPercent;
  final int? batteryMv;
  final bool? batteryCharging;
  final int? batteryMinutesRemaining;
  final List<BatteryHistoryEntry> batteryHistory;

  const DeviceStats({
    required this.conversationsToday,
    required this.totalConversations,
    required this.totalMemories,
    required this.poolSize,
    this.batteryPercent,
    this.batteryMv,
    this.batteryCharging,
    this.batteryMinutesRemaining,
    this.batteryHistory = const [],
  });

  factory DeviceStats.fromJson(Map<String, dynamic> json) {
    return DeviceStats(
      conversationsToday: json['conversationsToday'] as int? ?? 0,
      totalConversations: json['totalConversations'] as int? ?? 0,
      totalMemories: json['totalMemories'] as int? ?? 0,
      poolSize: json['poolSize'] as int? ?? 0,
      batteryPercent: json['batteryPercent'] as int?,
      batteryMv: json['batteryMv'] as int?,
      batteryCharging: json['batteryCharging'] as bool?,
      batteryMinutesRemaining: json['batteryMinutesRemaining'] as int?,
      batteryHistory: (json['batteryHistory'] as List<dynamic>?)
              ?.map((e) =>
                  BatteryHistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  static const Object _unset = Object();

  DeviceStats copyWith({
    int? conversationsToday,
    int? totalConversations,
    int? totalMemories,
    int? poolSize,
    Object? batteryPercent = _unset,
    Object? batteryMv = _unset,
    Object? batteryCharging = _unset,
    Object? batteryMinutesRemaining = _unset,
    List<BatteryHistoryEntry>? batteryHistory,
  }) {
    return DeviceStats(
      conversationsToday: conversationsToday ?? this.conversationsToday,
      totalConversations: totalConversations ?? this.totalConversations,
      totalMemories: totalMemories ?? this.totalMemories,
      poolSize: poolSize ?? this.poolSize,
      batteryPercent: identical(batteryPercent, _unset)
          ? this.batteryPercent
          : batteryPercent as int?,
      batteryMv:
          identical(batteryMv, _unset) ? this.batteryMv : batteryMv as int?,
      batteryCharging: identical(batteryCharging, _unset)
          ? this.batteryCharging
          : batteryCharging as bool?,
      batteryMinutesRemaining: identical(batteryMinutesRemaining, _unset)
          ? this.batteryMinutesRemaining
          : batteryMinutesRemaining as int?,
      batteryHistory: batteryHistory ?? this.batteryHistory,
    );
  }
}

class BatteryHistoryEntry {
  final DateTime timestamp;
  final int percent;
  final int mv;
  final bool charging;

  const BatteryHistoryEntry({
    required this.timestamp,
    required this.percent,
    required this.mv,
    required this.charging,
  });

  factory BatteryHistoryEntry.fromJson(Map<String, dynamic> json) {
    return BatteryHistoryEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      percent: json['percent'] as int? ?? 0,
      mv: json['mv'] as int? ?? 0,
      charging: json['charging'] as bool? ?? false,
    );
  }
}
