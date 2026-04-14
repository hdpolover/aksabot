enum OtaState { idle, triggered, inProgress, complete, error }

class OtaStatus {
  final OtaState state;
  final int progress; // 0–100
  final String? phase; // 'downloading' | 'verified' | 'flashing'
  final String? error;
  final String? version;

  const OtaStatus({
    required this.state,
    required this.progress,
    this.phase,
    this.error,
    this.version,
  });

  static const idle = OtaStatus(state: OtaState.idle, progress: 0);

  bool get isActive =>
      state == OtaState.triggered || state == OtaState.inProgress;

  static OtaState _stateFromString(String s) {
    switch (s) {
      case 'triggered':
        return OtaState.triggered;
      case 'in_progress':
        return OtaState.inProgress;
      case 'complete':
        return OtaState.complete;
      case 'error':
        return OtaState.error;
      default:
        return OtaState.idle;
    }
  }

  factory OtaStatus.fromJson(Map<String, dynamic> json) {
    return OtaStatus(
      state: _stateFromString(json['state'] as String? ?? 'idle'),
      progress: json['progress'] as int? ?? 0,
      phase: json['phase'] as String?,
      error: json['error'] as String?,
      version: json['version'] as String?,
    );
  }
}
