#include "vision.h"
#include "websocket.h"
#include "camera.h"
#include <esp_camera.h>

// Minimal base64 encoder for JPEG frames
static const char B64_CHARS[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static String base64Encode(const uint8_t* data, size_t len) {
    String out;
    out.reserve((len / 3 + 1) * 4 + 4);
    for (size_t i = 0; i < len; i += 3) {
        uint8_t b0 = data[i];
        uint8_t b1 = (i + 1 < len) ? data[i + 1] : 0;
        uint8_t b2 = (i + 2 < len) ? data[i + 2] : 0;
        out += B64_CHARS[b0 >> 2];
        out += B64_CHARS[((b0 & 3) << 4) | (b1 >> 4)];
        out += (i + 1 < len) ? B64_CHARS[((b1 & 15) << 2) | (b2 >> 6)] : '=';
        out += (i + 2 < len) ? B64_CHARS[b2 & 63] : '=';
    }
    return out;
}

// Vision modes
enum class VisionMode { CONVERSATION_ONLY, ALWAYS_ON };

static QueueHandle_t _frameQueue = nullptr;
static volatile bool _sending = false;          // true = actively sending frames
static volatile VisionMode _mode = VisionMode::CONVERSATION_ONLY;
static volatile bool _captureMode = false;      // true = capture 8 frames for enrollment
static volatile int _captureCount = 0;
static const int CAPTURE_FRAMES = 8;
static const int CAPTURE_INTERVAL_MS = 500;

// Vision loop task — runs on Core 1, priority 2
static void visionTask(void*) {
    const TickType_t framePeriod = pdMS_TO_TICKS(1000); // 1fps
    TickType_t lastWake = xTaskGetTickCount();

    while (true) {
        vTaskDelayUntil(&lastWake, framePeriod);

        if (!ws::connected()) continue;

        bool shouldSend = (_mode == VisionMode::ALWAYS_ON) || _sending;
        if (!shouldSend && !_captureMode) continue;

        camera_fb_t* fb = nullptr;
        if (xQueueReceive(_frameQueue, &fb, pdMS_TO_TICKS(100)) != pdTRUE || !fb) continue;

        // Copy to PSRAM and release camera buffer immediately
        uint8_t* buf = (uint8_t*)ps_malloc(fb->len);
        size_t len = fb->len;
        if (buf) memcpy(buf, fb->buf, len);
        camera::returnFrame(fb);
        if (!buf) continue;

        if (_captureMode) {
            // Enrollment: send raw binary JPEG (no base64 — avoids 40KB String allocation)
            ws::sendBinary(buf, len);
            _captureCount++;
            if (_captureCount >= CAPTURE_FRAMES) {
                _captureMode = false;
                _captureCount = 0;
                ws::send("vision:enroll_frames_done", "{}");
                Serial.println("[VISION] Enrollment capture complete");
            }
            free(buf);
            vTaskDelay(pdMS_TO_TICKS(CAPTURE_INTERVAL_MS));
        } else {
            // Recognition frame: send raw binary JPEG directly
            ws::sendBinary(buf, len);
            free(buf);
        }
    }
}

namespace vision {

void init(QueueHandle_t frameQueue) {
    _frameQueue = frameQueue;
    xTaskCreatePinnedToCore(visionTask, "vision", 8192, nullptr, 2, nullptr, 1);
    Serial.println("[VISION] Vision task started (conversation-only mode)");
}

void onEvent(const String& event, const String& data) {
    if (event == "vision:start") {
        _sending = true;
        Serial.println("[VISION] Sending frames (conversation active)");
    } else if (event == "vision:stop") {
        _sending = false;
        Serial.println("[VISION] Frame sending paused");
    } else if (event == "vision:capture") {
        _captureMode = true;
        _captureCount = 0;
        Serial.println("[VISION] Starting enrollment capture (8 frames)");
    } else if (event == "config:update") {
        // Check for vision_mode in data string: "conversation" or "always"
        if (data.indexOf("\"always\"") >= 0) {
            _mode = VisionMode::ALWAYS_ON;
            Serial.println("[VISION] Mode: always-on");
        } else if (data.indexOf("\"conversation\"") >= 0) {
            _mode = VisionMode::CONVERSATION_ONLY;
            Serial.println("[VISION] Mode: conversation-only");
        }
    }
}

bool isSending() {
    return _sending || (_mode == VisionMode::ALWAYS_ON);
}

} // namespace vision
