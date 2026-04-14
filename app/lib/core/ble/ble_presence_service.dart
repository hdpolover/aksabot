import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presence detection via a persistent GATT connection to the ESP32.
///
/// ## Why GATT connection instead of repeated scanning
///
/// The ESP32 advertises as "Aksabot" with service UUID 0xFFE0. The phone
/// connects to it once and the OS (CoreBluetooth on iOS, Android Bluetooth
/// stack) maintains the connection in the background — even when the app is
/// suspended.  Connection state changes wake the app so it can report
/// arrived / departed to the backend.
///
/// Repeated scanning (the previous approach) was paused by iOS when the app
/// was backgrounded because the scan had no service UUID filter.  A
/// persistent GATT connection sidesteps this entirely: the OS owns the
/// connection state machine, not a Dart timer.
///
/// ## Limitation
///
/// When the app is **terminated** (swiped away from the app switcher), the
/// OS closes the GATT connection.  There is no way to prevent this on iOS;
/// on Android a foreground service would be required.  For the common case
/// — app is backgrounded but not killed — this approach works correctly.
///
/// ## Flow
///
/// 1. `startScanning()` — scan with a 0xFFE0 UUID filter (iOS-background-safe)
///    until "Aksabot" is found.
/// 2. Connect with `autoConnect: true` — the OS reconnects automatically if
///    the connection drops temporarily (e.g., the user walked just outside
///    BLE range and came back quickly).
/// 3. `connectionState` stream: `connected` → report arrived; `disconnected`
///    (after grace period) → report departed.
/// 4. `stopScanning()` — disconnect and clean up.
class BlePresenceService {
  static const _prefEnabled = 'presence_enabled';
  static const _prefRssiThreshold = 'presence_rssi_threshold';
  static const _prefGracePeriod = 'presence_grace_period';
  static const _prefSilentWake = 'presence_silent_wake';
  static const _prefDeviceId = 'presence_device_id';

  static const _targetName = 'Aksabot';
  static const _targetServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const _scanTimeoutSec = 30; // give up initial scan after 30s; retry loop takes over

  // ── State ─────────────────────────────────────────────────────────────

  bool get isScanning => _scanActive || _connected;

  bool _scanActive = false;
  bool _connected = false;

  /// Whether the ESP32 is currently connected (= user at desk).
  bool get isPresent => _connected;

  String? _deviceId;         // backend device ID (not BLE device ID)
  BluetoothDevice? _device;  // the discovered ESP32

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Timer? _graceTimer;
  Timer? _retryTimer;        // restart scan if connect never happened

  String? lastError;

  // ── Callbacks ─────────────────────────────────────────────────────────

  /// Invoked on PRESENT → AWAY or AWAY → PRESENT transitions.
  Future<void> Function(String deviceId, String event, int awaySeconds)?
      onPresenceChanged;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  Future<bool> startScanning() async {
    lastError = null;

    if (!await loadEnabled()) return false;

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

    _scanActive = true;
    _startScan();
    return true;
  }

  Future<void> stopScanning() async {
    _scanActive = false;
    _graceTimer?.cancel();
    _graceTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    await _scanSub?.cancel();
    _scanSub = null;

    try { await FlutterBluePlus.stopScan(); } catch (_) {}

    await _connSub?.cancel();
    _connSub = null;

    if (_device != null) {
      try { await _device!.disconnect(); } catch (_) {}
      _device = null;
    }

    _connected = false;
  }

  // ── Scan ──────────────────────────────────────────────────────────────

  void _startScan() {
    if (!_scanActive) return;

    // Cancel any previous scan subscription before starting a new one.
    _scanSub?.cancel();
    _scanSub = null;
    try { FlutterBluePlus.stopScan(); } catch (_) {}

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (_isTarget(r)) {
          _onDeviceFound(r.device);
          return;
        }
      }
    });

    FlutterBluePlus.startScan(
      // Service UUID filter allows iOS to continue scanning in the background.
      // Without a filter, iOS pauses the scan when the app is suspended.
      withServices: [Guid(_targetServiceUuid)],
      timeout: const Duration(seconds: _scanTimeoutSec),
    ).catchError((e) {
      lastError = 'Scan error: $e';
    });

    // If scan expires without finding the device, retry after a short pause.
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: _scanTimeoutSec + 5), () {
      if (_scanActive && !_connected) _startScan();
    });
  }

  bool _isTarget(ScanResult r) {
    return r.advertisementData.advName == _targetName ||
        r.device.platformName == _targetName ||
        r.device.advName == _targetName;
  }

  void _onDeviceFound(BluetoothDevice device) {
    // Stop scanning — we have a target, now connect.
    _scanSub?.cancel();
    _scanSub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    try { FlutterBluePlus.stopScan(); } catch (_) {}

    _device = device;
    _connect(device);
  }

  // ── Connection ────────────────────────────────────────────────────────

  void _connect(BluetoothDevice device) {
    _connSub?.cancel();
    _connSub = device.connectionState.listen(_onConnectionState);

    device.connect(
      // autoConnect: true — the OS (CoreBluetooth / Android Bluetooth)
      // will reconnect automatically when the device re-appears in range.
      // This is the key to background operation: the OS handles reconnect
      // without needing the Dart timer loop to restart scanning.
      autoConnect: true,
      timeout: const Duration(seconds: 30),
    ).catchError((e) {
      lastError = 'Connect error: $e';
      // Fall back to scanning so we can try again.
      if (_scanActive) {
        Future.delayed(const Duration(seconds: 5), () {
          if (_scanActive && !_connected) _startScan();
        });
      }
    });
  }

  void _onConnectionState(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.connected) {
      _graceTimer?.cancel();
      _graceTimer = null;

      if (!_connected) {
        _connected = true;
        _reportArrived();
      }
    } else if (state == BluetoothConnectionState.disconnected) {
      if (_connected) {
        _connected = false;
        _startGraceTimer();
      } else if (_scanActive) {
        // Never reached "arrived" — device went away before we connected.
        // autoConnect will keep trying; nothing to do here.
      }
    }
  }

  // ── Grace period ──────────────────────────────────────────────────────

  /// Start a grace timer before reporting departure.
  ///
  /// [autoConnect: true] reconnects quickly if the user just stepped slightly
  /// out of range.  The grace period ensures we don't report "departed" for
  /// momentary BLE drops (stairwell, metal door) before autoConnect fires.
  void _startGraceTimer() async {
    final gracePeriod = await loadGracePeriod();
    _graceTimer?.cancel();
    _graceTimer = Timer(Duration(seconds: gracePeriod), () {
      if (!_connected && _scanActive) {
        _reportDeparted();
      }
    });
  }

  // ── Reporting ─────────────────────────────────────────────────────────

  void _reportArrived() {
    if (_deviceId == null || onPresenceChanged == null) return;
    onPresenceChanged!(_deviceId!, 'arrived', 0);
  }

  void _reportDeparted() {
    if (_deviceId == null || onPresenceChanged == null) return;
    onPresenceChanged!(_deviceId!, 'departed', 0);
  }

  // ── Configuration ─────────────────────────────────────────────────────

  Future<void> configureDevice(String deviceId) async {
    _deviceId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDeviceId, deviceId);
  }

  Future<String?> _loadDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefDeviceId);
  }

  Future<void> restoreState() async {
    final enabled = await loadEnabled();
    if (enabled) await startScanning();
  }

  // ── Persisted settings ────────────────────────────────────────────────

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
