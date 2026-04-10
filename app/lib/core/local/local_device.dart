import 'package:equatable/equatable.dart';

/// A device that has been provisioned locally (BLE or SoftAP) but not yet
/// registered with the backend. Persisted in SharedPreferences.
///
/// Once backend registration happens (Step 4), the device gains a server-side
/// ID and this record can be promoted or discarded.
class LocalDevice extends Equatable {
  final String id;         // e.g. "local_1713600000000"
  final String name;       // set during provisioning
  final String ssid;       // the Wi-Fi network the device joined
  final DateTime pairedAt;
  final String? localIp;   // filled by mDNS discovery (Step 3)

  const LocalDevice({
    required this.id,
    required this.name,
    required this.ssid,
    required this.pairedAt,
    this.localIp,
  });

  LocalDevice copyWith({String? name, String? localIp}) => LocalDevice(
        id: id,
        name: name ?? this.name,
        ssid: ssid,
        pairedAt: pairedAt,
        localIp: localIp ?? this.localIp,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ssid': ssid,
        'pairedAt': pairedAt.toIso8601String(),
        if (localIp != null) 'localIp': localIp,
      };

  factory LocalDevice.fromJson(Map<String, dynamic> json) => LocalDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        ssid: json['ssid'] as String,
        pairedAt: DateTime.parse(json['pairedAt'] as String),
        localIp: json['localIp'] as String?,
      );

  @override
  List<Object?> get props => [id, name, ssid, pairedAt, localIp];
}
