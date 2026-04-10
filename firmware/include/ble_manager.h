#pragma once
#include <cstdint>

/// BLE GATT server for device provisioning and presence detection.
///
/// Services:
///   0xFFE0 — WiFi provisioning (SSID, password, status)
///   0xFFE1 — Device auth (token, auth status)
///   0xFFE2 — Device control (volume, brightness)
///   0xFFE3 — Device status (battery, WiFi RSSI, uptime)
///
/// Presence scanning:
///   Scans for Flutter app advertising 0xFFE4 and feeds RSSI to presence_detector.
namespace ble_manager {

/// Initialize NimBLE, create GATT server, start advertising.
void init();

/// Block until WiFi credentials have been written via BLE.
/// Returns true when provisioned, false on timeout.
bool waitForProvisioning(uint32_t timeoutMs = 0);

/// Returns true if WiFi credentials were received via BLE this boot.
bool isProvisioned();

/// Start/stop BLE advertising.
void startAdvertising();
void stopAdvertising();

/// Notify WiFi status to connected BLE client.
/// 0=disconnected, 1=connecting, 2=connected, 3=failed
void notifyWifiStatus(uint8_t status);

/// Notify auth status to connected BLE client.
/// 0=no token, 1=token stored, 2=token validated
void notifyAuthStatus(uint8_t status);

/// Start BLE scanning for presence (0xFFE4 UUID).
/// Feeds RSSI to presence_detector automatically.
void startPresenceScan();
void stopPresenceScan();

/// Returns true if a BLE client is currently connected.
bool isClientConnected();

/// Update readable status characteristics (call periodically).
void updateStatus(uint8_t batteryPercent, int8_t wifiRssi, uint32_t uptimeSeconds);

/// Tick presence scanning — restarts scans after each cycle.
/// Call from loop() at ~10ms intervals.
void tickPresenceScan(uint32_t nowMs);

}  // namespace ble_manager
