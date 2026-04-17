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

uint8_t getVolume();       // 0-100, default 50
bool setVolume(uint8_t volume);

uint8_t getBrightness();   // 0-100, default 70
bool setBrightness(uint8_t brightness);

// ── Presence detection settings ───────────────────────

bool getPresenceEnabled();             // default false
bool setPresenceEnabled(bool enabled);

/// Last confirmed presence state. Persisted so the display dot shows the
/// correct state immediately on reboot, before the first WS event arrives.
bool getPresencePresent();             // default false
bool setPresencePresent(bool present);

int8_t getPresenceRssiThreshold();     // default -75
bool setPresenceRssiThreshold(int8_t rssi);

uint8_t getPresenceGracePeriodSec();   // default 45
bool setPresenceGracePeriodSec(uint8_t seconds);

// ── Display transcript ────────────────────────────────

/// Returns whether the transcript overlay is enabled. Default: false.
bool getDisplayTranscript();
bool setDisplayTranscript(bool enabled);

// ── Guest mode ────────────────────────────────────────

/// Guest mode pauses memory retrieval + extraction on the backend. Persisted
/// here so the face/LED indicators show the right state immediately on boot,
/// before the first config:update arrives. Default: false.
bool getGuestMode();
bool setGuestMode(bool enabled);

// ── Face style ────────────────────────────────────────

/// Returns the stored face style ID (0=ORBIT, 1=NOVA). Default: 1 (NOVA).
uint8_t getFaceStyle();
bool setFaceStyle(uint8_t styleId);

// ── Face colors ───────────────────────────────────────

/// Background color as 24-bit RGB (0xRRGGBB). Default: 0x000000 (black).
uint32_t getFaceBgColor();
bool setFaceBgColor(uint32_t color);

/// Eye body color as 24-bit RGB (0xRRGGBB). Default: 0xDADCE6 (soft white).
/// Applies to NOVA eye rectangles and ORBIT eye sclera.
uint32_t getFaceEyeColor();
bool setFaceEyeColor(uint32_t color);

/// Mouth color as 24-bit RGB (0xRRGGBB). Default: 0xFFFFFF (white).
/// Applied to all expression mouth shapes uniformly.
uint32_t getFaceMouthColor();
bool setFaceMouthColor(uint32_t color);

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

// ── Force provisioning ────────────────────────────────

/// Returns true if a remote re-provision was requested (via device:provision WS event).
/// One-shot: cleared by setForceProvision(false) immediately after being read at boot.
bool getForceProvision();
bool setForceProvision(bool enabled);

// ── Factory reset ─────────────────────────────────────

/// Erase all stored values. Device will need re-provisioning.
bool eraseAll();

}  // namespace nvs_store
