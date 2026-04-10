#pragma once

/// Lightweight HTTP server running in STA mode after Wi-Fi connects.
/// Serves device identity and status so the Flutter app can discover this
/// device on the local network (complementing mDNS / aksabot.local).
namespace device_server {

/// Start the server on port 80. Call once after Wi-Fi connects.
/// version: firmware version string (stored internally).
void start(const char* version);

/// Process pending HTTP requests. Call every ~50ms from loop().
void tick();

/// Stop the server (e.g., before deep sleep or reset).
void stop();

}  // namespace device_server
