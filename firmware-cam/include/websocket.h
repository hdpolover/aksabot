#pragma once
#include <Arduino.h>
#include <functional>

namespace ws {

using MessageCallback = std::function<void(const String& event, const String& data)>;

void init(const char* host, uint16_t port, const char* token, MessageCallback onMessage);
void loop();   // call periodically from task — handles reconnect + poll
void send(const String& event, const String& data);
bool connected();

} // namespace ws
