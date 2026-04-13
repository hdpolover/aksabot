#pragma once
#include <cstdint>

namespace wifi_manager {

/// Initialize Wi-Fi in STA mode and connect.
/// If NVS has provisioned credentials, uses those. Otherwise falls back
/// to compile-time WIFI_SSID/WIFI_PASS from config.h.
void init();

/// Returns true if connected to Wi-Fi.
bool isConnected();

/// Block until Wi-Fi is connected (with timeout_ms, 0 = forever).
bool waitForConnection(uint32_t timeout_ms = 0);

/// Reconnect using new credentials (e.g., after BLE provisioning).
void reconnect(const char* ssid, const char* password);

// ── SoftAP provisioning ───────────────────────────────────────

/// Start Wi-Fi in AP+STA mode, creating a hotspot with the given name.
/// Also starts an HTTP server on 192.168.4.1 that accepts:
///   POST /provision  { "ssid": "...", "password": "..." }
void startAP(const char* apName);

/// Stop the SoftAP and HTTP server, switch back to STA mode.
void stopAP();

/// Returns true if credentials were received via the SoftAP HTTP endpoint.
bool isAPProvisioned();

/// Process pending HTTP requests. Call periodically (for example,
/// every ~50–200ms) while AP is active.
void tickAP();

/// Call from main loop to drive exponential-backoff reconnection.
/// WiFi.setAutoReconnect(true) can silently stop retrying after repeated
/// failures (e.g., router restart). This provides an explicit fallback.
void tick();

}  // namespace wifi_manager
