#pragma once

/// Lightweight HTTP server running in STA mode after Wi-Fi connects.
/// Serves device identity and status so the Flutter app can discover this
/// device on the local network (complementing mDNS / aksabot.local).
namespace device_server {

/// Start the server on port 80. Call once after Wi-Fi connects.
/// version: firmware version string (stored internally).
/// Guards against multiple calls — safe to call after reconnect.
void start(const char* version);

/// Enable or disable setup mode. While active, POST /token accepts a
/// device token from the Flutter app after backend registration.
/// Call setSetupMode(true) on first-boot before calling start(), and
/// setSetupMode(false) (or it auto-clears) after a token is received.
void setSetupMode(bool active);

/// Process pending HTTP requests. Call every ~50ms from loop().
void tick();

/// Stop the server (e.g., before deep sleep or reset).
void stop();

/// Returns true (once) if a device token was received via POST /token
/// since the last call. Call from loop() to trigger WS reconnect.
bool consumeNewToken();

/// Returns true (once) if the app requested a backend reconnect via POST /reconnect.
bool consumeReconnect();

/// Returns true (once) if the app requested a wake via POST /wake.
bool consumeWake();

}  // namespace device_server
