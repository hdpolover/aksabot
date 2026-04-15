import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presence detection via a persistent GATT connection to the ESP32.
///
/// ## Connection strategy (AirPods pattern)
///
/// After the very first successful GATT connection, we store the ESP32's BLE
/// platform ID (`_prefBleDeviceId`).  On every subsequent `startScanning()`
/// call we skip the scan entirely and call `connect(autoConnect: true)` on the
/// known device handle — identical to how an iPhone reconnects to AirPods
/// without scanning.  The OS (CoreBluetooth / Android BluetoothGatt) owns the
/// low-power monitoring; we just respond to connection-state callbacks.
///
/// A scan is only needed the very first time (no stored BLE ID yet) or if the
/// direct-connect attempt doesn't succeed within [_directConnectTimeoutSec]
/// (e.g., device was replaced).
///
/// ## Lifecycle / background reliability
///
/// Dart `Timer`s freeze when iOS fully suspends the app, so the old retry-timer
/// approach was unreliable.  The fix: call `resumeIfNeeded()` from an
/// `AppLifecycleObserver` whenever the app returns to the foreground.
/// `autoConnect: true` keeps the OS-level reconnect alive in the background
/// without any Dart timer involvement.
///
/// ## Limitation
///
/// When the app is **terminated** (swiped away), the OS closes the GATT
/// connection.  On next launch `startScanning()` / `restoreState()` re-arms
/// the direct-connect — usually completes in < 1 s if the device is in range.
class BlePresenceService {
  // ── Preference keys ────────────────────────────────────────────────────
  static const _prefEnabled        = 'presence_enabled';
  static const _prefRssiThreshold  = 'presence_rssi_threshold';
  static const _prefGracePeriod    = 'presence_grace_period';
  static const _prefSilentWake     = 'presence_silent_wake';
  static const _prefDeviceId       = 'presence_device_id';      // backend device ID
  static const _prefBleDeviceId    = 'presence_ble_device_id';  // ESP32 BLE platform ID

  static const _targetName        = 'Aksabot';
  static const _targetServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

  /// How long to wait for a direct-connect before falling back to a scan.
  static const _directConnectTimeoutSec = 12;

  /// How long a single scan window runs before giving up and retrying.
  static const _scanTimeoutSec = 30;

  // ── State ──────────────────────────────────────────────────────────────

  bool get isScanning => _scanActive || _connected;
  bool get isPresent  => _connected;

  bool _scanActive = false;
  bool _connected  = false;

  String?          _deviceId;  // backend device ID
  BluetoothDevice? _device;    // the ESP32 BLE handle

  StreamSubscription<List<ScanResult>>?         _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<BluetoothAdapterState>?    _adapterSub;
  Timer? _graceTimer;
  Timer? _fallbackTimer;  // direct-connect → scan fallback; scan → retry

  String? lastError;

  // ── Callbacks ─────────────────────────────────────────────────────────

  Future<void> Function(String deviceId, String event, int awaySeconds)?
      onPresenceChanged;

  // ── Public API ────────────────────────────────────────────────────────

  /// Start presence detection.
  ///
  /// If a BLE device ID is already stored, attempts a direct connect (no scan).
  /// Otherwise starts a scan to find the ESP32 for the first time.
  ///
  /// Also arms the adapter-state watcher so if Bluetooth is toggled off then
  /// back on, scanning restarts automatically without user intervention.
  Future<bool> startScanning() async {
    lastError = null;

    if (!await loadEnabled()) return false;

    _deviceId = await _loadDeviceId();
    if (_deviceId == null) {
      lastError = 'No device configured for presence detection';
      return false;
    }

    // Watch for Bluetooth being turned on after an off period.
    _adapterSub ??= FlutterBluePlus.adapterState.listen(_onAdapterState);

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      // Bluetooth is currently off; the adapter-state watcher will restart us
      // when it comes back on.
      lastError = 'Bluetooth is off';
      return false;
    }

    _scanActive = true;

    final storedBleId = await _loadBleDeviceId();
    if (storedBleId != null) {
      // Check if the OS already has an active connection from a previous
      // autoConnect session — if so, just attach the listener (no connect call
      // needed, which would generate an unnecessary connection event).
      final already = _findConnectedSystemDevice(storedBleId);
      if (already != null) {
        _device = already;
        _connSub?.cancel();
        _connSub = already.connectionState.listen(_onConnectionState);
        // Treat as arrived immediately.
        if (!_connected) {
          _connected = true;
          _reportArrived();
        }
      } else {
        // Known device but not currently connected: direct-connect (AirPods pattern).
        await _tryDirectConnect(storedBleId);
      }
    } else {
      // First time: scan to discover the ESP32.
      _startScan();
    }

    return true;
  }

  /// Stop presence detection and clean up all resources.
  Future<void> stopScanning() async {
    _scanActive = false;

    _graceTimer?.cancel();
    _graceTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    await _adapterSub?.cancel();
    _adapterSub = null;

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

  /// Called by the AppLifecycleObserver on `resumed`.
  ///
  /// Dart timers freeze when iOS suspends the app. This is the recovery hook:
  /// whenever the user brings the app to the foreground we check if scanning
  /// should be active and restart if needed.
  Future<void> resumeIfNeeded() async {
    if (_connected) return;   // already connected — nothing to do
    if (_scanActive) return;  // already trying — let it continue
    // Either the grace timer fired (departed state) or the app was backgrounded
    // before connecting. Either way, restart the detection cycle.
    await startScanning();
  }

  /// Restore state on app launch.
  Future<void> restoreState() async {
    final enabled = await loadEnabled();
    if (enabled) await startScanning();
  }

  /// Clear the stored BLE device ID (call when user removes the device or
  /// factory-resets, so the next enable does a fresh scan).
  Future<void> clearStoredDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefBleDeviceId);
  }

  // ── Direct connect (AirPods pattern) ──────────────────────────────────

  Future<void> _tryDirectConnect(String bleDeviceId) async {
    try {
      final device = BluetoothDevice(remoteId: DeviceIdentifier(bleDeviceId));
      _device = device;
      _connect(device);

      // If the device isn't in range right now, autoConnect will wait.
      // But if it takes too long (stale BLE ID after device replacement),
      // fall back to a fresh scan.
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(
        const Duration(seconds: _directConnectTimeoutSec),
        () {
          if (_scanActive && !_connected) {
            // Direct connect is taking too long — clear stale ID and scan.
            clearStoredDevice();
            _device = null;
            _startScan();
          }
        },
      );
    } catch (e) {
      lastError = 'Direct connect error: $e';
      _startScan();
    }
  }

  // ── Scan ──────────────────────────────────────────────────────────────

  void _startScan() {
    if (!_scanActive) return;

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
      // Service UUID filter is required for iOS background scanning.
      withServices: [Guid(_targetServiceUuid)],
      timeout: const Duration(seconds: _scanTimeoutSec),
    ).catchError((e) {
      lastError = 'Scan error: $e';
    });

    // Restart scan if it expires without finding the device.
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(
      const Duration(seconds: _scanTimeoutSec + 5),
      () {
        if (_scanActive && !_connected) _startScan();
      },
    );
  }

  bool _isTarget(ScanResult r) =>
      r.advertisementData.advName == _targetName ||
      r.device.platformName == _targetName ||
      r.device.advName == _targetName;

  void _onDeviceFound(BluetoothDevice device) {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _scanSub?.cancel();
    _scanSub = null;
    try { FlutterBluePlus.stopScan(); } catch (_) {}

    _device = device;
    _connect(device);
  }

  // ── Connection ────────────────────────────────────────────────────────

  void _connect(BluetoothDevice device) {
    _connSub?.cancel();
    _connSub = device.connectionState.listen(_onConnectionState);

    device
        .connect(
          // autoConnect: true — the OS reconnects when the device re-appears.
          // This is the key to background operation and AirPods-like behaviour:
          // the OS handles reconnect at the kernel level, not a Dart timer.
          autoConnect: true,
          timeout: const Duration(seconds: 30),
        )
        .catchError((e) {
          lastError = 'Connect error: $e';
          if (_scanActive && !_connected) {
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
      _fallbackTimer?.cancel();  // cancel direct-connect fallback — we made it
      _fallbackTimer = null;

      // Persist the BLE device ID so future launches skip the scan.
      if (_device != null) _saveBleDeviceId(_device!.remoteId.str);

      if (!_connected) {
        _connected = true;
        _reportArrived();
      }
    } else if (state == BluetoothConnectionState.disconnected) {
      if (_connected) {
        _connected = false;
        _startGraceTimer();
      }
      // If we were in the middle of a direct-connect attempt (autoConnect),
      // the OS will keep trying in the background — no action needed here.
    }
  }

  // ── Adapter state ─────────────────────────────────────────────────────

  void _onAdapterState(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.on) {
      // BT was just turned back on — restart the detection cycle if it should
      // be running but isn't (e.g., startScanning returned false earlier).
      if (!_connected && !_scanActive) {
        startScanning();
      }
    } else {
      // BT turned off: mark as disconnected without firing departure immediately
      // (the grace timer handles that if it was already running).
      if (_connected) {
        _connected = false;
        _startGraceTimer();
      }
      _scanActive = false;
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
    }
  }

  // ── System device lookup ──────────────────────────────────────────────

  /// Returns the already-connected system device matching [bleDeviceId], or
  /// null if no such connection exists at the OS level.
  BluetoothDevice? _findConnectedSystemDevice(String bleDeviceId) {
    try {
      return FlutterBluePlus.connectedDevices
          .firstWhere((d) => d.remoteId.str == bleDeviceId);
    } catch (_) {
      return null;
    }
  }

  // ── Grace period ──────────────────────────────────────────────────────

  void _startGraceTimer() async {
    final gracePeriod = await loadGracePeriod();
    _graceTimer?.cancel();
    _graceTimer = Timer(Duration(seconds: gracePeriod), () {
      if (!_connected) {
        _reportDeparted();
        // Re-arm: keep monitoring so the next arrival is detected.
        // Reset _scanActive so startScanning() can run again.
        _scanActive = false;
        startScanning();
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

  Future<String?> _loadBleDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefBleDeviceId);
  }

  Future<void> _saveBleDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBleDeviceId, id);
  }

  // ── Persisted settings ────────────────────────────────────────────────

  Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
    if (!enabled) await clearStoredDevice();
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
