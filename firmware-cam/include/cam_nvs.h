#pragma once
#include <Arduino.h>

namespace cam_nvs {

void init();

// WiFi — falls back to credentials.h compile-time constants
const char* wifiSsid();
const char* wifiPass();

// Backend — reads backend_url from NVS (same key as main firmware).
// Parses wss://host/path → host + port=443, or ws://host:port/path → host + port.
// Falls back to BACKEND_HOST / BACKEND_PORT from credentials.h.
const char* backendHost();
uint16_t    backendPort();

// Device token — reads dev_token from NVS, falls back to DEVICE_TOKEN from credentials.h.
const char* deviceToken();

} // namespace cam_nvs
