#pragma once
#include <cstdint>
#include <cstddef>

/// Non-volatile storage wrapper for Aksabot.
///
/// Persists Wi-Fi credentials, device token, and device settings
/// across reboots. Provisioned via BLE; read on startup.
namespace nvs_store {

/// Open NVS namespace. Must be called before any read/write.
bool init();

// ── Wi-Fi credentials ─────────────────────────────────

bool getWifiSsid(char* buf, size_t bufLen);
bool setWifiSsid(const char* ssid);

bool getWifiPassword(char* buf, size_t bufLen);
bool setWifiPassword(const char* password);

/// Returns true if Wi-Fi credentials have been provisioned.
bool hasWifiCredentials();

// ── Backend connection ────────────────────────────────

bool getBackendUrl(char* buf, size_t bufLen);
bool setBackendUrl(const char* url);

bool getDeviceToken(char* buf, size_t bufLen);
bool setDeviceToken(const char* token);

/// Returns true if a device token has been provisioned.
bool hasDeviceToken();

// ── Device settings ───────────────────────────────────

uint8_t getVolume();       // 0-100, default 80
bool setVolume(uint8_t volume);

uint8_t getBrightness();   // 0-100, default 70
bool setBrightness(uint8_t brightness);

// ── Presence detection settings ───────────────────────

bool getPresenceEnabled();             // default false
bool setPresenceEnabled(bool enabled);

int8_t getPresenceRssiThreshold();     // default -75
bool setPresenceRssiThreshold(int8_t rssi);

uint8_t getPresenceGracePeriodSec();   // default 45
bool setPresenceGracePeriodSec(uint8_t seconds);

// ── Face style ────────────────────────────────────────

/// Returns the stored face style ID (0=ORBIT, 1=NOVA). Default: 1 (NOVA).
uint8_t getFaceStyle();
bool setFaceStyle(uint8_t styleId);

// ── Idle display mode ─────────────────────────────────

/// Returns the stored idle display mode as a string ("face", "clock", "status").
/// Default: "face".
bool getIdleDisplayMode(char* buf, size_t bufLen);
bool setIdleDisplayMode(const char* mode);

// ── Setup state ───────────────────────────────────────

/// Returns true if this device has never completed first-time setup.
/// Becomes false after markSetupComplete(). Resets to true after eraseAll().
bool isFirstBoot();

/// Mark setup as complete. Call after first successful WiFi connection.
bool markSetupComplete();

// ── Factory reset ─────────────────────────────────────

/// Erase all stored values. Device will need re-provisioning.
bool eraseAll();

}  // namespace nvs_store
