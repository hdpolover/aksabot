#include "nvs_store.h"
#include <Preferences.h>
#include <Arduino.h>

// ESP32 Arduino Preferences wraps NVS with a clean key-value API.
static Preferences prefs;
static bool initialized = false;

static const char* NAMESPACE = "aksabot";

// ── Key constants ──────────────────────────────────────
static const char* K_WIFI_SSID    = "wifi_ssid";
static const char* K_WIFI_PASS    = "wifi_pass";
static const char* K_BACKEND_URL  = "backend_url";
static const char* K_DEVICE_TOKEN = "dev_token";
static const char* K_VOLUME       = "volume";
static const char* K_BRIGHTNESS   = "brightness";
static const char* K_PRES_ENABLED = "pres_en";
static const char* K_PRES_RSSI    = "pres_rssi";
static const char* K_PRES_GRACE   = "pres_grace";
static const char* K_DISP_TRANSCRIPT = "disp_transcript";
static const char* K_FACE_STYLE   = "face_style";
static const char* K_IDLE_DISP    = "idle_disp";
static const char* K_SETUP_DONE   = "setup_done";
static const char* K_FORCE_PROV   = "force_prov";

// ── Helpers ────────────────────────────────────────────

static bool getString(const char* key, char* buf, size_t bufLen) {
    if (!initialized) return false;
    String val = prefs.getString(key, "");
    if (val.isEmpty()) return false;
    strncpy(buf, val.c_str(), bufLen - 1);
    buf[bufLen - 1] = '\0';
    return true;
}

static bool setString(const char* key, const char* value) {
    if (!initialized) return false;
    size_t written = prefs.putString(key, value);
    return written > 0;
}

// ── Init ───────────────────────────────────────────────

bool nvs_store::init() {
    if (initialized) return true;

    bool ok = prefs.begin(NAMESPACE, false);  // read-write mode
    if (!ok) {
        Serial.println("[NVS] Failed to open namespace");
        return false;
    }

    initialized = true;
    Serial.printf("[NVS] Initialized — free entries: %u\n", prefs.freeEntries());
    return true;
}

// ── Wi-Fi credentials ──────────────────────────────────

bool nvs_store::getWifiSsid(char* buf, size_t bufLen) {
    return getString(K_WIFI_SSID, buf, bufLen);
}

bool nvs_store::setWifiSsid(const char* ssid) {
    bool ok = setString(K_WIFI_SSID, ssid);
    if (ok) Serial.printf("[NVS] Wi-Fi SSID saved (%zu chars)\n", strlen(ssid));
    return ok;
}

bool nvs_store::getWifiPassword(char* buf, size_t bufLen) {
    return getString(K_WIFI_PASS, buf, bufLen);
}

bool nvs_store::setWifiPassword(const char* password) {
    bool ok = setString(K_WIFI_PASS, password);
    if (ok) Serial.println("[NVS] Wi-Fi password saved");
    return ok;
}

bool nvs_store::hasWifiCredentials() {
    if (!initialized) return false;
    return prefs.isKey(K_WIFI_SSID) && prefs.isKey(K_WIFI_PASS);
}

// ── Backend connection ─────────────────────────────────

bool nvs_store::getBackendUrl(char* buf, size_t bufLen) {
    return getString(K_BACKEND_URL, buf, bufLen);
}

bool nvs_store::setBackendUrl(const char* url) {
    bool ok = setString(K_BACKEND_URL, url);
    if (ok) Serial.printf("[NVS] Backend URL saved: %s\n", url);
    return ok;
}

bool nvs_store::getDeviceToken(char* buf, size_t bufLen) {
    return getString(K_DEVICE_TOKEN, buf, bufLen);
}

bool nvs_store::setDeviceToken(const char* token) {
    bool ok = setString(K_DEVICE_TOKEN, token);
    if (ok) Serial.println("[NVS] Device token saved");
    return ok;
}

bool nvs_store::hasDeviceToken() {
    if (!initialized) return false;
    return prefs.isKey(K_DEVICE_TOKEN);
}

// ── Device settings ────────────────────────────────────

uint8_t nvs_store::getVolume() {
    if (!initialized) return 50;
    return prefs.getUChar(K_VOLUME, 50);
}

bool nvs_store::setVolume(uint8_t volume) {
    if (!initialized) return false;
    return prefs.putUChar(K_VOLUME, volume) > 0;
}

uint8_t nvs_store::getBrightness() {
    if (!initialized) return 70;
    return prefs.getUChar(K_BRIGHTNESS, 70);
}

bool nvs_store::setBrightness(uint8_t brightness) {
    if (!initialized) return false;
    return prefs.putUChar(K_BRIGHTNESS, brightness) > 0;
}

// ── Presence detection settings ────────────────────────

bool nvs_store::getPresenceEnabled() {
    if (!initialized) return false;
    return prefs.getBool(K_PRES_ENABLED, false);
}

bool nvs_store::setPresenceEnabled(bool enabled) {
    if (!initialized) return false;
    return prefs.putBool(K_PRES_ENABLED, enabled) > 0;
}

int8_t nvs_store::getPresenceRssiThreshold() {
    if (!initialized) return -75;
    return prefs.getChar(K_PRES_RSSI, -75);
}

bool nvs_store::setPresenceRssiThreshold(int8_t rssi) {
    if (!initialized) return false;
    return prefs.putChar(K_PRES_RSSI, rssi) > 0;
}

uint8_t nvs_store::getPresenceGracePeriodSec() {
    if (!initialized) return 45;
    return prefs.getUChar(K_PRES_GRACE, 45);
}

bool nvs_store::setPresenceGracePeriodSec(uint8_t seconds) {
    if (!initialized) return false;
    return prefs.putUChar(K_PRES_GRACE, seconds) > 0;
}

// ── Display transcript ─────────────────────────────────

bool nvs_store::getDisplayTranscript() {
    if (!initialized) return false;
    return prefs.getBool(K_DISP_TRANSCRIPT, false);
}

bool nvs_store::setDisplayTranscript(bool enabled) {
    if (!initialized) return false;
    return prefs.putBool(K_DISP_TRANSCRIPT, enabled) > 0;
}

// ── Face style ─────────────────────────────────────────

uint8_t nvs_store::getFaceStyle() {
    if (!initialized) return 1;  // default: NOVA
    return prefs.getUChar(K_FACE_STYLE, 1);
}

bool nvs_store::setFaceStyle(uint8_t styleId) {
    if (!initialized) return false;
    return prefs.putUChar(K_FACE_STYLE, styleId) > 0;
}

// ── Idle display mode ──────────────────────────────────

bool nvs_store::getIdleDisplayMode(char* buf, size_t bufLen) {
    const char* def = "face";
    if (!initialized || !prefs.isKey(K_IDLE_DISP)) {
        // Key not yet written — return default silently.
        // Calling prefs.getString() when the key is absent triggers an internal
        // Preferences warning even when a default is supplied; isKey() avoids it.
        strncpy(buf, def, bufLen - 1);
        buf[bufLen - 1] = '\0';
        return true;
    }
    String val = prefs.getString(K_IDLE_DISP, def);
    strncpy(buf, val.c_str(), bufLen - 1);
    buf[bufLen - 1] = '\0';
    return true;
}

bool nvs_store::setIdleDisplayMode(const char* mode) {
    return setString(K_IDLE_DISP, mode);
}

// ── Setup state ────────────────────────────────────────

bool nvs_store::isFirstBoot() {
    if (!initialized) return true;
    return !prefs.getBool(K_SETUP_DONE, false);
}

bool nvs_store::markSetupComplete() {
    if (!initialized) return false;
    bool ok = prefs.putBool(K_SETUP_DONE, true) > 0;
    if (ok) Serial.println("[NVS] Setup marked complete");
    return ok;
}

// ── Force provisioning ─────────────────────────────────

bool nvs_store::getForceProvision() {
    if (!initialized) return false;
    return prefs.getBool(K_FORCE_PROV, false);
}

bool nvs_store::setForceProvision(bool enabled) {
    if (!initialized) return false;
    return prefs.putBool(K_FORCE_PROV, enabled) > 0;
}

// ── Factory reset ──────────────────────────────────────

bool nvs_store::eraseAll() {
    if (!initialized) return false;
    bool ok = prefs.clear();
    if (ok) Serial.println("[NVS] All data erased");
    return ok;
}
