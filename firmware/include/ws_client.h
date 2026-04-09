#pragma once
#include <ArduinoWebsockets.h>
#include <functional>

namespace ws_client {

/// Callback types for received events
using JsonCallback = std::function<void(const char* event, const char* data)>;
using BinaryCallback = std::function<void(const uint8_t* data, size_t len)>;

/// Initialize WebSocket client. Call after Wi-Fi is connected.
void init(JsonCallback onJson, BinaryCallback onBinary);

/// Connect to the backend. Non-blocking — returns immediately.
void connect();

/// Must be called from a loop/task to process incoming messages.
void poll();

/// Returns true if WebSocket is connected.
bool isConnected();

/// Send a JSON event: {"event":"<name>","data":<data>}
void sendEvent(const char* event, const char* jsonData = nullptr);

/// Send binary data (Opus audio chunk).
void sendBinary(const uint8_t* data, size_t len);

/// Disconnect gracefully.
void disconnect();

}  // namespace ws_client
