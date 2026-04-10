import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_device.dart';

/// Persists locally-provisioned Aksabot devices in SharedPreferences.
///
/// Used before (and independently of) the backend. Devices are stored as a
/// JSON-encoded list under [_key].
class LocalDeviceStore {
  LocalDeviceStore._();

  static const _key = 'local_devices_v1';

  // ── Read ─────────────────────────────────────────────────────

  static Future<List<LocalDevice>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final devices = <LocalDevice>[];
    for (final s in raw) {
      try {
        final json = jsonDecode(s) as Map<String, dynamic>;
        devices.add(LocalDevice.fromJson(json));
      } catch (_) {
        // Skip corrupted entries
      }
    }
    // Most recently paired first
    devices.sort((a, b) => b.pairedAt.compareTo(a.pairedAt));
    return devices;
  }

  static Future<LocalDevice?> getById(String id) async {
    final all = await getAll();
    try {
      return all.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Write ─────────────────────────────────────────────────────

  /// Saves or replaces a device (matched by id).
  static Future<void> save(LocalDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getAll();
    final updated = [
      device,
      ...devices.where((d) => d.id != device.id),
    ];
    await prefs.setStringList(
      _key,
      updated.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  static Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getAll();
    final updated = devices.where((d) => d.id != id).toList();
    await prefs.setStringList(
      _key,
      updated.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // ── Factory ───────────────────────────────────────────────────

  /// Creates a new local device with a timestamped ID.
  static LocalDevice create({
    required String name,
    required String ssid,
  }) {
    return LocalDevice(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      ssid: ssid,
      pairedAt: DateTime.now(),
    );
  }
}
