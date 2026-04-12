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

  /// Returns a filtered stream of Aksabot scan results.
  ///
  /// **Subscribe to this stream BEFORE calling [startScan].**
  /// `FlutterBluePlus.scanResults` is a broadcast stream — events emitted
  /// before a listener is attached are lost. With `allowDuplicates: false`
  /// (the default), each device is only reported once, so a late subscription
  /// permanently misses it.
  Stream<List<ScanResult>> get scanResultsFiltered =>
      FlutterBluePlus.scanResults.map(
        (results) => results
            .where((r) {
              final name = r.device.platformName.toLowerCase();
              final advName = r.advertisementData.advName.toLowerCase();
              // Match by name OR by the Aksabot WiFi provisioning service UUID.
              // NimBLE v2.5+ doesn't always include the device name in the
              // advertisement/scan-response data, but the 0xFFE0 service UUID
              // is reliably present.
              final hasAksabotService = r.advertisementData.serviceUuids
                  .any((uuid) => uuid == Guid('0000ffe0-0000-1000-8000-00805f9b34fb'));
              return name.contains('aksabot') ||
                  advName.contains('aksabot') ||
                  hasAksabotService;
            })
            .toList(),
      );

  /// Starts scanning for Aksabot devices. Subscribe to [scanResultsFiltered]
  /// first, then call this.
  void startScan({Duration timeout = const Duration(seconds: 10)}) {
    FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
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

  /// Writes Wi-Fi credentials and returns raw byte notifications.
  ///
  /// The connected notification includes the IP: `[2, ip_bytes...]`.
  /// Use this to extract the device IP and skip mDNS discovery.
  Future<Stream<List<int>>> writeWifiCredentialsRaw(String ssid, String password) async {
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

    // Write credentials
    await ssidChar.write(utf8.encode(ssid), withoutResponse: false);
    await passChar.write(utf8.encode(password), withoutResponse: false);

    // Return raw byte stream — caller parses status + IP
    return statusChar.onValueReceived;
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

  /// Writes the device token (and optionally backend URL) to the ESP32.
  ///
  /// For provisioning, pass `"token\nbackendUrl"` as the payload so the
  /// firmware has everything it needs to connect to WebSocket after WiFi.
  Future<void> writeDeviceToken(String payload) async {
    final authSvc = _findService(BleConstants.authService);
    if (authSvc == null) throw BleProvisioningException('Auth service not found');

    final tokenChar = _findCharacteristic(authSvc, BleConstants.deviceToken);
    if (tokenChar == null) {
      throw BleProvisioningException('Token characteristic not found');
    }

    await tokenChar.write(utf8.encode(payload), withoutResponse: false);
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
