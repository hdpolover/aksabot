#pragma once
#include <cstdint>

/// WiFi AP-based provisioning server.
///
/// Creates a WiFi hotspot ("Aksabot-XXXX") with a simple HTTP API.
/// The Flutter app connects to this AP and sends credentials via HTTP.
///
/// Endpoints:
///   GET  /            → device info JSON (name, version, mac)
///   POST /provision   → receive WiFi creds + device token
///   GET  /status      → provisioning status
namespace wifi_provision {

/// Start the AP and HTTP server. Call during setup() when provisioning is needed.
/// apName: hotspot name (e.g., "Aksabot-A1B2")
/// apPassword: hotspot password (empty string = open network)
void start(const char* apName, const char* apPassword = "");

/// Stop the AP and HTTP server. Call after provisioning completes.
void stop();

/// Returns true if provisioning credentials have been received via HTTP.
bool isProvisioned();

/// Block until credentials are received. Returns true on success.
bool waitForProvisioning(uint32_t timeoutMs = 0);

/// Get the AP IP address (typically 192.168.4.1).
const char* getApIp();

/// Get the AP name being broadcast.
const char* getApName();

}  // namespace wifi_provision
