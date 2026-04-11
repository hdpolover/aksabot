import 'dart:async';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_constants.dart';

/// Manages BLE presence advertising so the ESP32 can detect the phone nearby.
///
/// The Flutter app acts as a BLE peripheral, advertising the presence service
/// UUID (0xFFE4). The ESP32 periodically scans for this UUID and reads the
/// RSSI to determine whether the user is at their desk.
class BlePresenceService {
  static const _prefEnabled = 'presence_enabled';
  static const _prefRssiThreshold = 'presence_rssi_threshold';
  static const _prefGracePeriod = 'presence_grace_period';
  static const _prefSilentWake = 'presence_silent_wake';

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  /// Starts advertising the presence service UUID.
  ///
  /// Uses low-power mode suitable for background operation.
  /// The ESP32 will scan for this advertisement to detect the user's phone.
  /// Last failure reason — readable by the UI for diagnostics.
  String? lastError;

  Future<bool> startAdvertising() async {
    lastError = null;

    final supported = await _peripheral.isSupported;
    if (!supported) {
      lastError = 'BLE peripheral mode not supported on this device';
      return false;
    }

    // Check permission first
    final permState = await _peripheral.requestPermission();
    if (permState == BluetoothPeripheralState.denied ||
        permState == BluetoothPeripheralState.permanentlyDenied) {
      lastError = 'Bluetooth permission denied (state: ${permState.name})';
      return false;
    }
    if (permState == BluetoothPeripheralState.turnedOff) {
      lastError = 'Bluetooth is turned off';
      return false;
    }
    if (permState == BluetoothPeripheralState.unsupported) {
      lastError = 'BLE advertising not supported';
      return false;
    }

    final advertiseData = AdvertiseData(
      serviceUuid: '0000ffe4-0000-1000-8000-00805f9b34fb',
      includeDeviceName: false,
    );

    final settings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeLowPower,
      connectable: false,
      timeout: 0, // Advertise indefinitely
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerLow,
    );

    try {
      final result = await _peripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: settings,
      );

      _isAdvertising = result == BluetoothPeripheralState.ready ||
          result == BluetoothPeripheralState.granted ||
          result == BluetoothPeripheralState.limited;

      if (!_isAdvertising) {
        _isAdvertising = await _peripheral.isAdvertising;
      }

      if (!_isAdvertising) {
        lastError = 'Advertising failed to start (state: ${result.name})';
      }

      return _isAdvertising;
    } catch (e) {
      lastError = 'Advertising error: $e';
      _isAdvertising = false;
      return false;
    }
  }

  /// Stops presence advertising.
  Future<void> stopAdvertising() async {
    await _peripheral.stop();
    _isAdvertising = false;
  }

  /// Checks if BLE peripheral mode is supported on this device.
  Future<bool> get isSupported => _peripheral.isSupported;

  /// Checks current advertising state from the platform.
  Future<bool> checkAdvertisingState() async {
    _isAdvertising = await _peripheral.isAdvertising;
    return _isAdvertising;
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

  /// Restores advertising state from saved preferences.
  /// Call this on app startup to resume advertising if it was previously enabled.
  Future<void> restoreState() async {
    final enabled = await loadEnabled();
    if (enabled) {
      await startAdvertising();
    }
  }
}
