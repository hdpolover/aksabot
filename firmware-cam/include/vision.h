#pragma once
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

namespace vision {

void init(QueueHandle_t frameQueue);
void onEvent(const String& event, const String& data);
bool isSending();

} // namespace vision
