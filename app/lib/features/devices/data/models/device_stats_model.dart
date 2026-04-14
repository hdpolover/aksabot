class DeviceStats {
  final int conversationsToday;
  final int totalConversations;
  final int totalMemories;
  final int poolSize;
  final int? batteryPercent; // 0–100 = percent, 255 = USB powered, null = unknown

  const DeviceStats({
    required this.conversationsToday,
    required this.totalConversations,
    required this.totalMemories,
    required this.poolSize,
    this.batteryPercent,
  });

  factory DeviceStats.fromJson(Map<String, dynamic> json) {
    return DeviceStats(
      conversationsToday: json['conversationsToday'] as int? ?? 0,
      totalConversations: json['totalConversations'] as int? ?? 0,
      totalMemories: json['totalMemories'] as int? ?? 0,
      poolSize: json['poolSize'] as int? ?? 0,
      batteryPercent: json['batteryPercent'] as int?,
    );
  }

  static const Object _unset = Object();

  DeviceStats copyWith({
    int? conversationsToday,
    int? totalConversations,
    int? totalMemories,
    int? poolSize,
    Object? batteryPercent = _unset,
  }) {
    return DeviceStats(
      conversationsToday: conversationsToday ?? this.conversationsToday,
      totalConversations: totalConversations ?? this.totalConversations,
      totalMemories: totalMemories ?? this.totalMemories,
      poolSize: poolSize ?? this.poolSize,
      batteryPercent: identical(batteryPercent, _unset)
          ? this.batteryPercent
          : batteryPercent as int?,
    );
  }
}
