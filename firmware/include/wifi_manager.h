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

}  // namespace wifi_manager
