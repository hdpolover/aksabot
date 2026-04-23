# Face Recognition — firmware-cam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WebSocket client and vision frame sender to the ESP32-CAM firmware so it connects to the aksabot backend, registers as a camera device, sends JPEG frames at 1fps for face recognition, and handles vision control events (start/stop/capture/config).

**Architecture:** firmware-cam gains two new modules: `websocket` (ArduinoWebsockets client with reconnect) and `vision` (1fps frame timer, vision:frame sender, event dispatcher). The capture loop already produces frames via frameQueue — vision taps into it. WebSocket events control whether frames are sent (conversation-only vs always-on mode).

**Tech Stack:** PlatformIO + Arduino (ESP32), ArduinoWebsockets (gilmaimon/ArduinoWebsockets@^0.5.3), existing WiFiServer + FreeRTOS tasks.

**Note:** No automated tests for embedded C++. Verification is build + serial output inspection.

---

## File Structure

```
firmware-cam/
  platformio.ini              ← MODIFY: add ArduinoWebsockets lib_deps
  include/
    credentials.h             ← MODIFY: add BACKEND_HOST, BACKEND_PORT, DEVICE_TOKEN
    websocket.h               ← CREATE
    vision.h                  ← CREATE
  src/
    websocket.cpp             ← CREATE
    vision.cpp                ← CREATE
    main.cpp                  ← MODIFY: init websocket + vision tasks
```

---

## Task 1: platformio.ini + credentials.h

**Files:**
- Modify: `firmware-cam/platformio.ini`
- Modify: `firmware-cam/include/credentials.h`

- [ ] **Step 1: Add ArduinoWebsockets to platformio.ini**

Open `firmware-cam/platformio.ini`. Replace the full file contents:
```ini
[env:esp32cam]
platform = espressif32
board = esp32cam
framework = arduino

board_build.flash_size = 4MB
board_build.partitions = huge_app.csv

build_flags =
    -DBOARD_HAS_PSRAM
    -DCORE_DEBUG_LEVEL=0

lib_deps =
    gilmaimon/ArduinoWebsockets@^0.5.3

monitor_speed = 115200
upload_speed = 460800
upload_port = /dev/tty.usbserial-21240
monitor_port = /dev/tty.usbserial-21240
```

- [ ] **Step 2: Add backend credentials to credentials.h**

Open `firmware-cam/include/credentials.h`. Replace with:
```cpp
#pragma once
#define WIFI_SSID     "PT MIT"
#define WIFI_PASSWORD "PTMIT7788"

// Backend WebSocket connection
// Get DEVICE_TOKEN from the backend after claiming the ESP32-CAM device
// Run: POST /devices (body: {name:"ESP32-CAM", type:"camera"}) with JWT auth
// Then copy the deviceToken field here
#define BACKEND_HOST  "192.168.10.x"  // replace with backend IP or hostname
#define BACKEND_PORT  4280
#define DEVICE_TOKEN  "paste-device-token-here"

// The aksabot main device ID to pair with (from Flutter app device list)
// This is set via backend PATCH /devices/:cameraId settingsJson.pairedDeviceId
// Leave empty — set via backend API after claiming both devices
```

- [ ] **Step 3: Verify build compiles**

```bash
cd firmware-cam && pio run
```
Expected: Build succeeds. ArduinoWebsockets downloads and compiles.

- [ ] **Step 4: Commit**

```bash
git add firmware-cam/platformio.ini firmware-cam/include/credentials.h
git commit -m "chore(firmware-cam): add ArduinoWebsockets dep + backend credentials"
```

---

## Task 2: websocket.cpp/h

**Files:**
- Create: `firmware-cam/include/websocket.h`
- Create: `firmware-cam/src/websocket.cpp`

- [ ] **Step 1: Create websocket.h**

Create `firmware-cam/include/websocket.h`:
```cpp
#pragma once
#include <Arduino.h>
#include <functional>

namespace ws {

using MessageCallback = std::function<void(const String& event, const String& data)>;

void init(const char* host, uint16_t port, const char* token, MessageCallback onMessage);
void loop();   // call periodically from task — handles reconnect + poll
void send(const String& event, const String& data);
void sendBinary(const String& event, const uint8_t* buf, size_t len);
bool connected();

} // namespace ws
```

- [ ] **Step 2: Create websocket.cpp**

Create `firmware-cam/src/websocket.cpp`:
```cpp
#include "websocket.h"
#include "credentials.h"
#include <ArduinoWebsockets.h>

using namespace websockets;

static WebsocketsClient _client;
static ws::MessageCallback _onMessage;
static const char* _host;
static uint16_t _port;
static const char* _token;
static unsigned long _lastConnectAttempt = 0;
static bool _connected = false;

static const unsigned long RECONNECT_INTERVAL_MS = 5000;

static void onEvent(WebsocketsEvent event, String data) {
    if (event == WebsocketsEvent::ConnectionOpened) {
        _connected = true;
        Serial.println("[WS] Connected to backend");
    } else if (event == WebsocketsEvent::ConnectionClosed) {
        _connected = false;
        Serial.println("[WS] Disconnected from backend");
    } else if (event == WebsocketsEvent::GotPing) {
        _client.pong();
    }
}

static void onMessage(WebsocketsMessage msg) {
    if (!msg.isText()) return;
    // Parse {"event":"...", "data":...} — minimal JSON parse
    String raw = msg.data();
    int evStart = raw.indexOf("\"event\":\"");
    if (evStart < 0) return;
    evStart += 9;
    int evEnd = raw.indexOf("\"", evStart);
    if (evEnd < 0) return;
    String event = raw.substring(evStart, evEnd);

    int dataStart = raw.indexOf("\"data\":");
    String data = "";
    if (dataStart >= 0) {
        data = raw.substring(dataStart + 7);
        // trim trailing }
        while (data.endsWith("}")) data = data.substring(0, data.length() - 1);
        data.trim();
    }
    _onMessage(event, data);
}

static bool connectToBackend() {
    Serial.printf("[WS] Connecting to %s:%d\n", _host, _port);
    _client.setInsecure(); // no SSL cert verification (local network)
    _client.onEvent(onEvent);
    _client.onMessage(::onMessage);

    // Attach device token as Authorization header
    _client.addHeader("Authorization", String("Bearer ") + _token);

    bool ok = _client.connect(_host, _port, "/ws");
    if (!ok) {
        Serial.println("[WS] Connection failed");
    }
    return ok;
}

namespace ws {

void init(const char* host, uint16_t port, const char* token, MessageCallback onMessage) {
    _host = host;
    _port = port;
    _token = token;
    _onMessage = onMessage;
    connectToBackend();
}

void loop() {
    if (_client.available()) {
        _client.poll();
    } else if (!_connected) {
        unsigned long now = millis();
        if (now - _lastConnectAttempt > RECONNECT_INTERVAL_MS) {
            _lastConnectAttempt = now;
            connectToBackend();
        }
    }
}

void send(const String& event, const String& data) {
    if (!_connected) return;
    String msg = "{\"event\":\"" + event + "\",\"data\":" + data + "}";
    _client.send(msg);
}

void sendBinary(const String& event, const uint8_t* buf, size_t len) {
    // Send event name as text first, then binary frame
    send(event, "\"pending\"");
    _client.sendBinary((const char*)buf, len);
}

bool connected() {
    return _connected;
}

} // namespace ws
```

- [ ] **Step 3: Build to verify compilation**

```bash
cd firmware-cam && pio run
```
Expected: Compiles without errors.

- [ ] **Step 4: Commit**

```bash
git add firmware-cam/include/websocket.h firmware-cam/src/websocket.cpp
git commit -m "feat(firmware-cam): add WebSocket client with reconnect"
```

---

## Task 3: vision.cpp/h

**Files:**
- Create: `firmware-cam/include/vision.h`
- Create: `firmware-cam/src/vision.cpp`

The vision module taps into `frameQueue` (defined in main.cpp) to get frames, encodes them as base64, and sends as `vision:frame` WebSocket messages at 1fps. It also handles `vision:start`, `vision:stop`, `vision:capture`, and `config:update` events.

- [ ] **Step 1: Create vision.h**

Create `firmware-cam/include/vision.h`:
```cpp
#pragma once
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

namespace vision {

void init(QueueHandle_t frameQueue);
void onEvent(const String& event, const String& data);
bool isSending();

} // namespace vision
```

- [ ] **Step 2: Create vision.cpp**

Create `firmware-cam/src/vision.cpp`:
```cpp
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
            // Enrollment capture: send base64 frames, collect CAPTURE_FRAMES
            // Build JSON array element for this frame
            String b64 = base64Encode(buf, len);
            // Send each frame individually as vision:enroll_frame (backend accumulates)
            ws::send("vision:enroll_frame", "\"" + b64 + "\"");
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
            // Normal recognition frame
            String b64 = base64Encode(buf, len);
            ws::send("vision:frame", "\"" + b64 + "\"");
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
```

- [ ] **Step 3: Build to verify compilation**

```bash
cd firmware-cam && pio run
```
Expected: Compiles without errors.

- [ ] **Step 4: Commit**

```bash
git add firmware-cam/include/vision.h firmware-cam/src/vision.cpp
git commit -m "feat(firmware-cam): add vision module (1fps frame sender + enrollment capture)"
```

---

## Task 4: main.cpp Integration

**Files:**
- Modify: `firmware-cam/src/main.cpp`

- [ ] **Step 1: Add includes and WebSocket task to main.cpp**

Open `firmware-cam/src/main.cpp`. Add includes at top (after existing includes):
```cpp
#include "websocket.h"
#include "vision.h"
#include "credentials.h"
```

- [ ] **Step 2: Add WebSocket message handler**

In `main.cpp`, add this function before `setup()`:
```cpp
void onWsMessage(const String& event, const String& data) {
    vision::onEvent(event, data);
}
```

- [ ] **Step 3: Add WebSocket task**

Add a new FreeRTOS task function for the WebSocket poll loop:
```cpp
// Core 1: poll WebSocket, handle reconnect
void wsLoop(void*) {
    while (true) {
        ws::loop();
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
```

- [ ] **Step 4: Initialize WebSocket and vision in setup()**

In `setup()`, after the WiFi connect block and before `xTaskCreatePinnedToCore` calls, add:
```cpp
// Register camera device with backend (one-time on boot)
// The backend will accept device token from credentials.h
ws::init(BACKEND_HOST, BACKEND_PORT, DEVICE_TOKEN, onWsMessage);
Serial.println("[BOOT] WebSocket connecting to backend");

// Vision frame sender — taps into frameQueue
vision::init(frameQueue);
```

- [ ] **Step 5: Add wsLoop task in setup()**

After existing `xTaskCreatePinnedToCore` calls, add:
```cpp
xTaskCreatePinnedToCore(wsLoop, "ws", 8192, nullptr, 2, nullptr, 1);
```

- [ ] **Step 6: Full main.cpp after changes**

The complete setup() task creation block should look like:
```cpp
xTaskCreatePinnedToCore(captureLoop, "capture", 8192, nullptr, 5, nullptr, 1);
xTaskCreatePinnedToCore(mjpegTask,   "mjpeg",   8192, nullptr, 4, nullptr, 1);
xTaskCreatePinnedToCore(serverLoop,  "server",  8192, nullptr, 3, nullptr, 1);
xTaskCreatePinnedToCore(wsLoop,      "ws",      8192, nullptr, 2, nullptr, 1);
// vision task is started inside vision::init()
```

- [ ] **Step 7: Build**

```bash
cd firmware-cam && pio run
```
Expected: Compiles without errors.

- [ ] **Step 8: Flash and verify serial output**

```bash
cd firmware-cam && pio run --target upload && pio device monitor
```

Expected serial output:
```
[BOOT] ESP32-CAM firmware starting
[BOOT] OV3660 OK
[BOOT] WiFi connecting.....
[BOOT] IP=192.168.10.23
[WS] Connecting to 192.168.10.x:4280
[VISION] Vision task started (conversation-only mode)
[BOOT] MJPEG server on port 81
[BOOT] HTTP server started on port 80
[WS] Connected to backend     ← appears once backend is running with valid token
```

If backend not running: `[WS] Connection failed` then retry every 5s — expected.

- [ ] **Step 9: Commit**

```bash
git add firmware-cam/src/main.cpp
git commit -m "feat(firmware-cam): wire WebSocket + vision into main loop"
```

---

## Task 5: Backend Pairing Setup (Manual Steps)

These are one-time setup steps, not code changes.

- [ ] **Step 1: Create ESP32-CAM device on backend**

With backend running, use curl or Postman. First, get a JWT token for your account:
```bash
curl -X POST http://localhost:4280/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com","password":"yourpassword"}'
# Copy the access_token from response
```

Create the camera device:
```bash
curl -X POST http://localhost:4280/devices \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"ESP32-CAM","type":"camera"}'
# Copy deviceToken from response — paste into credentials.h DEVICE_TOKEN
# Copy id from response — this is the camera device ID
```

- [ ] **Step 2: Set pairedDeviceId on camera device**

Get your aksabot main device ID from the Flutter app (device detail page → stats).

```bash
curl -X PATCH http://localhost:4280/devices/<camera-device-id> \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"settingsJson":{"pairedDeviceId":"<aksabot-main-device-id>"}}'
```

- [ ] **Step 3: Reflash firmware-cam with real token**

Update `firmware-cam/include/credentials.h` DEVICE_TOKEN with the real token from Step 1.

```bash
cd firmware-cam && pio run --target upload
```

- [ ] **Step 4: Verify connection**

Backend logs should show:
```
Device <camera-id> (ESP32-CAM) connected
```

And firmware-cam serial:
```
[WS] Connected to backend
```

- [ ] **Step 5: Test face recognition end-to-end**

1. Enroll yourself: use Flutter app face recognition page → "Use desk camera" → enter name
2. Stand in front of ESP32-CAM
3. Backend logs should show: `Face match: Hendra (conf=0.85)`
4. Aksabot main device session should receive `face:identity` event
