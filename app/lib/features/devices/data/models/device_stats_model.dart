class DeviceStats {
  final int conversationsToday;
  final int totalConversations;
  final int totalMemories;
  final int poolSize;
  final int? batteryPercent; // 0–100 = percent, 255 = charging, null = unknown
  final int? batteryMv; // raw millivolts for diagnostics
  final bool? batteryCharging; // true if USB or voltage trending up

  const DeviceStats({
    required this.conversationsToday,
    required this.totalConversations,
    required this.totalMemories,
    required this.poolSize,
    this.batteryPercent,
    this.batteryMv,
    this.batteryCharging,
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
  }) {
    return DeviceStats(
      conversationsToday: conversationsToday ?? this.conversationsToday,
      totalConversations: totalConversations ?? this.totalConversations,
      totalMemories: totalMemories ?? this.totalMemories,
      poolSize: poolSize ?? this.poolSize,
      batteryPercent: identical(batteryPercent, _unset)
          ? this.batteryPercent
          : batteryPercent as int?,
      batteryMv: identical(batteryMv, _unset)
          ? this.batteryMv
          : batteryMv as int?,
      batteryCharging: identical(batteryCharging, _unset)
          ? this.batteryCharging
          : batteryCharging as bool?,
    );
  }
}
