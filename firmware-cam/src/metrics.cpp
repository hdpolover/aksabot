#include "metrics.h"
#include <Arduino.h>

static volatile int _frameCount = 0;
static volatile int _fps = 0;
static volatile int _frameMs = 0;
static unsigned long _lastFrameTime = 0;
static unsigned long _lastTickTime = 0;

namespace metrics {

void onFrame(size_t frameBytes) {
    (void)frameBytes;
    unsigned long now = millis();
    if (_lastFrameTime > 0) {
        _frameMs = (int)(now - _lastFrameTime);
    }
    _lastFrameTime = now;
    _frameCount++;
}

int fps()     { return _fps; }
int frameMs() { return _frameMs; }

void tick(bool motionDetected) {
    unsigned long now = millis();
    unsigned long elapsed = now - _lastTickTime;
    if (elapsed < 1000) return;
    _fps = (int)((_frameCount * 1000UL) / elapsed);
    Serial.printf("[METRICS] fps=%d frame_ms=%d heap=%luKB psram=%luKB motion=%d\n",
        _fps, _frameMs,
        ESP.getFreeHeap()  / 1024,
        ESP.getFreePsram() / 1024,
        motionDetected ? 1 : 0);
    _frameCount  = 0;
    _lastTickTime = now;
}

} // namespace metrics
