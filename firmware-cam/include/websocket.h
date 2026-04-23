#pragma once
#include <Arduino.h>
#include <functional>

namespace ws {

using MessageCallback = std::function<void(const String& event, const String& data)>;

void init(const char* host, uint16_t port, const char* token, MessageCallback onMessage);
void loop();   // call periodically from task — handles reconnect + poll
void send(const String& event, const String& data);
void sendBinary(const uint8_t* buf, size_t len);
bool connected();

} // namespace ws
