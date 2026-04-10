#pragma once
#include <cstdint>

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

// ── Factory reset ─────────────────────────────────────

/// Erase all stored values. Device will need re-provisioning.
bool eraseAll();

}  // namespace nvs_store
