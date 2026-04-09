import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// GATT service and characteristic UUIDs for Aksabot ESP32.
class BleConstants {
  BleConstants._();

  // ── Service UUIDs ────────────────────────────────────────────
  static final wifiService = Guid('0000ffe0-0000-1000-8000-00805f9b34fb');
  static final authService = Guid('0000ffe1-0000-1000-8000-00805f9b34fb');
  static final controlService = Guid('0000ffe2-0000-1000-8000-00805f9b34fb');
  static final statusService = Guid('0000ffe3-0000-1000-8000-00805f9b34fb');

  // ── Wi-Fi Provisioning (0xFFE0) ──────────────────────────────
  static final wifiSsid = Guid('0000ffe0-0001-1000-8000-00805f9b34fb');
  static final wifiPassword = Guid('0000ffe0-0002-1000-8000-00805f9b34fb');
  static final wifiStatus = Guid('0000ffe0-0003-1000-8000-00805f9b34fb');

  // ── Device Auth (0xFFE1) ─────────────────────────────────────
  static final deviceToken = Guid('0000ffe1-0001-1000-8000-00805f9b34fb');
  static final authStatus = Guid('0000ffe1-0002-1000-8000-00805f9b34fb');

  // ── Device Control (0xFFE2) ──────────────────────────────────
  static final volume = Guid('0000ffe2-0001-1000-8000-00805f9b34fb');
  static final brightness = Guid('0000ffe2-0002-1000-8000-00805f9b34fb');

  // ── Device Status (0xFFE3) ───────────────────────────────────
  static final battery = Guid('0000ffe3-0001-1000-8000-00805f9b34fb');
  static final wifiRssi = Guid('0000ffe3-0002-1000-8000-00805f9b34fb');
  static final uptime = Guid('0000ffe3-0003-1000-8000-00805f9b34fb');

  // ── Presence Advertising (0xFFE4) — app-side only ────────────
  static final presenceService = Guid('0000ffe4-0000-1000-8000-00805f9b34fb');

  // ── Wi-Fi Status Values ──────────────────────────────────────
  static const wifiDisconnected = 0;
  static const wifiConnecting = 1;
  static const wifiConnected = 2;
  static const wifiFailed = 3;

  // ── Auth Status Values ───────────────────────────────────────
  static const authNoToken = 0;
  static const authTokenStored = 1;
  static const authTokenValidated = 2;
}
