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
/// Use for provisioning flow (before WiFi connects).
void init();

/// Initialize NimBLE for scanning only (no GATT server, no advertising).
/// Use after WiFi is up to enable presence detection without the full
/// GATT overhead. Safe to call if init() was already called — becomes a no-op.
void initScanOnly();

/// Returns true if BLE has been initialized (via init() or initScanOnly()).
bool isInitialized();

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

/// Notify WiFi connected with IP address embedded in the payload.
/// Sends [2, ip_bytes...] so the app can skip mDNS discovery.
void notifyWifiConnectedWithIp(const char* ip);

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
