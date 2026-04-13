import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages presence detection by scanning for the ESP32's BLE advertisement.
///
/// The phone scans for a device named "Aksabot" (or matching a stored MAC
/// address) and measures RSSI. When the device is close enough, the app
/// reports arrival to the backend. When it drops below the threshold for the
/// full grace period, it reports departure.
///
/// This is the reverse of the original approach (where the phone advertised
/// and the ESP32 scanned) — scanning is more reliably supported across
/// Android OEMs than peripheral advertising.
class BlePresenceService {
  static const _prefEnabled = 'presence_enabled';
  static const _prefRssiThreshold = 'presence_rssi_threshold';
  static const _prefGracePeriod = 'presence_grace_period';
  static const _prefSilentWake = 'presence_silent_wake';
  static const _prefDeviceId = 'presence_device_id';

  static const _scanDurationSec = 5;
  static const _targetName = 'Aksabot';

  // ── State ─────────────────────────────────────────────────────

  bool _scanning = false;
  bool get isScanning => _scanning;

  _PresenceState _state = _PresenceState.away;
  DateTime? _lastSeen;
  DateTime? _leftAt;

  /// Whether the ESP32 is currently detected nearby.
  bool get isPresent => _state == _PresenceState.present;

  String? _deviceId;
  String? lastError;

  Timer? _scanTimer;

  // Callback invoked on state transitions — set by the caller to trigger
  // backend REST calls without creating a circular dependency.
  Future<void> Function(String deviceId, String event, int awaySeconds)?
      onPresenceChanged;

  // ── Lifecycle ─────────────────────────────────────────────────

  Future<bool> startScanning() async {
    lastError = null;

    final enabled = await loadEnabled();
    if (!enabled) return false;

    _deviceId = await _loadDeviceId();
    if (_deviceId == null) {
      lastError = 'No device configured for presence detection';
      return false;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      lastError = 'Bluetooth is off';
      return false;
    }

    _scanning = true;
    _scheduleNextScan();
    return true;
  }

  Future<void> stopScanning() async {
    _scanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  // ── Scan loop ─────────────────────────────────────────────────

  void _scheduleNextScan() {
    if (!_scanning) return;
    // Scan every scanDuration + 5s gap. When present, check less aggressively.
    final intervalSec = _state == _PresenceState.present ? 15 : 8;
    _scanTimer = Timer(Duration(seconds: intervalSec), _doScanCycle);
  }

  Future<void> _doScanCycle() async {
    if (!_scanning) return;

    int? bestRssi;

    try {
      final rssiThreshold = await loadRssiThreshold();

      // Scan without a name filter — Android's withNames OS-level filter silently
      // drops packets if the name isn't in the primary advertisement (e.g. NimBLE
      // puts it in scan response). We match by name ourselves after receiving all results.
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: _scanDurationSec),
      );

      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          if (_isTargetDevice(r)) {
            if (bestRssi == null || r.rssi > bestRssi) {
              bestRssi = r.rssi;
            }
          }
        }
      }

      await _processScanResult(bestRssi, rssiThreshold.round());
    } catch (e) {
      lastError = 'Scan error: $e';
    }

    _scheduleNextScan();
  }

  bool _isTargetDevice(ScanResult r) {
    return r.advertisementData.advName == _targetName ||
        r.device.platformName == _targetName ||
        r.device.advName == _targetName;
  }

  Future<void> _processScanResult(int? rssi, int threshold) async {
    final gracePeriod = await loadGracePeriod();

    if (rssi != null && rssi >= threshold) {
      // Device in range
      _lastSeen = DateTime.now();
      _leftAt = null;

      if (_state == _PresenceState.away) {
        _state = _PresenceState.present;
        await _reportArrived();
      } else {
        _state = _PresenceState.present;
      }
    } else {
      // Device not seen or below threshold
      if (_state == _PresenceState.present) {
        _state = _PresenceState.leaving;
        _leftAt = DateTime.now();
      } else if (_state == _PresenceState.leaving && _leftAt != null) {
        final elapsed = DateTime.now().difference(_leftAt!).inSeconds;
        if (elapsed >= gracePeriod) {
          _state = _PresenceState.away;
          await _reportDeparted();
        }
      }
    }
  }

  Future<void> _reportArrived() async {
    if (_deviceId == null || onPresenceChanged == null) return;
    final silentWakeMin = await loadSilentWakeMinutes();
    final awaySec = _lastSeen != null
        ? 0
        : (silentWakeMin * 60); // conservative if no prior seen time
    await onPresenceChanged!(_deviceId!, 'arrived', awaySec);
  }

  Future<void> _reportDeparted() async {
    if (_deviceId == null || onPresenceChanged == null) return;
    await onPresenceChanged!(_deviceId!, 'departed', 0);
  }

  // ── Configuration ─────────────────────────────────────────────

  /// Call this when the user selects a device for presence detection.
  Future<void> configureDevice(String deviceId) async {
    _deviceId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDeviceId, deviceId);
  }

  Future<String?> _loadDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefDeviceId);
  }

  /// Restores scanning on app startup if it was previously enabled.
  Future<void> restoreState() async {
    final enabled = await loadEnabled();
    if (enabled) {
      await startScanning();
    }
  }

  // ── Persisted Settings ────────────────────────────────────────

  Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
  }

  Future<double> loadRssiThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_prefRssiThreshold) ?? -75.0;
  }

  Future<void> saveRssiThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefRssiThreshold, value);
  }

  Future<int> loadGracePeriod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefGracePeriod) ?? 45;
  }

  Future<void> saveGracePeriod(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefGracePeriod, seconds);
  }

  Future<int> loadSilentWakeMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefSilentWake) ?? 5;
  }

  Future<void> saveSilentWakeMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefSilentWake, minutes);
  }
}

enum _PresenceState { away, present, leaving }
