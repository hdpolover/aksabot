import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_constants.dart';

/// High-level BLE provisioning operations for Aksabot ESP32.
///
/// Wraps flutter_blue_plus with Aksabot-specific GATT reads/writes.
class BleProvisioningService {
  BluetoothDevice? _device;
  List<BluetoothService> _services = [];

  BluetoothDevice? get connectedDevice => _device;
  bool get isConnected => _device != null;

  // ── Scanning ─────────────────────────────────────────────────

  /// Starts scanning for Aksabot devices (advertising 0xFFE0).
  /// Returns a stream of discovered devices.
  Stream<List<ScanResult>> startScan({Duration timeout = const Duration(seconds: 10)}) {
    FlutterBluePlus.startScan(
      withServices: [BleConstants.wifiService],
      timeout: timeout,
    );
    return FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // ── Connection ───────────────────────────────────────────────

  /// Connects to the given device and discovers services.
  Future<void> connect(BluetoothDevice device) async {
    await device.connect(timeout: const Duration(seconds: 10));
    _device = device;

    // Wait a moment for services to stabilize (some ESP32 firmware needs this)
    await Future.delayed(const Duration(milliseconds: 500));
    _services = await device.discoverServices();
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _services = [];
  }

  // ── Wi-Fi Provisioning ───────────────────────────────────────

  /// Writes Wi-Fi credentials to the ESP32 and waits for connection.
  ///
  /// Returns a stream of wifi status updates (0=disconnected, 1=connecting,
  /// 2=connected, 3=failed).
  Future<Stream<int>> writeWifiCredentials(String ssid, String password) async {
    final wifiSvc = _findService(BleConstants.wifiService);
    if (wifiSvc == null) throw BleProvisioningException('Wi-Fi service not found');

    final ssidChar = _findCharacteristic(wifiSvc, BleConstants.wifiSsid);
    final passChar = _findCharacteristic(wifiSvc, BleConstants.wifiPassword);
    final statusChar = _findCharacteristic(wifiSvc, BleConstants.wifiStatus);

    if (ssidChar == null || passChar == null || statusChar == null) {
      throw BleProvisioningException('Wi-Fi characteristics not found');
    }

    // Subscribe to status notifications first
    await statusChar.setNotifyValue(true);
    final statusStream = statusChar.onValueReceived.map(
      (value) => value.isNotEmpty ? value[0] : 0,
    );

    // Write credentials
    await ssidChar.write(utf8.encode(ssid), withoutResponse: false);
    await passChar.write(utf8.encode(password), withoutResponse: false);

    return statusStream;
  }

  /// Reads the current Wi-Fi connection status.
  Future<int> readWifiStatus() async {
    final wifiSvc = _findService(BleConstants.wifiService);
    if (wifiSvc == null) return BleConstants.wifiDisconnected;

    final statusChar = _findCharacteristic(wifiSvc, BleConstants.wifiStatus);
    if (statusChar == null) return BleConstants.wifiDisconnected;

    final value = await statusChar.read();
    return value.isNotEmpty ? value[0] : BleConstants.wifiDisconnected;
  }

  // ── Device Auth ──────────────────────────────────────────────

  /// Writes the device token to the ESP32 and waits for auth validation.
  ///
  /// Returns a stream of auth status updates (0=no token, 1=stored, 2=validated).
  Future<Stream<int>> writeDeviceToken(String token) async {
    final authSvc = _findService(BleConstants.authService);
    if (authSvc == null) throw BleProvisioningException('Auth service not found');

    final tokenChar = _findCharacteristic(authSvc, BleConstants.deviceToken);
    final statusChar = _findCharacteristic(authSvc, BleConstants.authStatus);

    if (tokenChar == null || statusChar == null) {
      throw BleProvisioningException('Auth characteristics not found');
    }

    // Subscribe to auth status notifications
    await statusChar.setNotifyValue(true);
    final statusStream = statusChar.onValueReceived.map(
      (value) => value.isNotEmpty ? value[0] : 0,
    );

    // Write token
    await tokenChar.write(utf8.encode(token), withoutResponse: false);

    return statusStream;
  }

  /// Reads the current auth status.
  Future<int> readAuthStatus() async {
    final authSvc = _findService(BleConstants.authService);
    if (authSvc == null) return BleConstants.authNoToken;

    final statusChar = _findCharacteristic(authSvc, BleConstants.authStatus);
    if (statusChar == null) return BleConstants.authNoToken;

    final value = await statusChar.read();
    return value.isNotEmpty ? value[0] : BleConstants.authNoToken;
  }

  // ── Device Control (volume/brightness) ───────────────────────

  Future<void> writeVolume(int volume) async {
    final svc = _findService(BleConstants.controlService);
    if (svc == null) return;
    final char = _findCharacteristic(svc, BleConstants.volume);
    if (char == null) return;
    await char.write([volume.clamp(0, 100)], withoutResponse: false);
  }

  Future<void> writeBrightness(int brightness) async {
    final svc = _findService(BleConstants.controlService);
    if (svc == null) return;
    final char = _findCharacteristic(svc, BleConstants.brightness);
    if (char == null) return;
    await char.write([brightness.clamp(0, 100)], withoutResponse: false);
  }

  // ── Helpers ──────────────────────────────────────────────────

  BluetoothService? _findService(Guid uuid) {
    for (final svc in _services) {
      if (svc.uuid == uuid) return svc;
    }
    return null;
  }

  BluetoothCharacteristic? _findCharacteristic(
    BluetoothService service,
    Guid uuid,
  ) {
    for (final char in service.characteristics) {
      if (char.uuid == uuid) return char;
    }
    return null;
  }
}

class BleProvisioningException implements Exception {
  final String message;
  const BleProvisioningException(this.message);

  @override
  String toString() => 'BleProvisioningException: $message';
}
