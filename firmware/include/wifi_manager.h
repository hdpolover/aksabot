#pragma once

namespace wifi_manager {

/// Initialize Wi-Fi in STA mode and connect.
void init();

/// Returns true if connected to Wi-Fi.
bool isConnected();

/// Block until Wi-Fi is connected (with timeout_ms, 0 = forever).
bool waitForConnection(uint32_t timeout_ms = 0);

}  // namespace wifi_manager
