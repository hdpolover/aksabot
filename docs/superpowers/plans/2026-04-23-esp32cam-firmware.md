# ESP32-CAM Custom Firmware Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Tasmota on AI-Thinker ESP32-CAM-MB with custom C++ firmware — dual-core MJPEG stream server with motion detection, runtime resolution control, browser UI, and serial metrics.

**Architecture:** Core 0 runs a dedicated capture loop (OV3660 grab → motion check → push to 1-slot queue). Core 1 runs the HTTP server (MJPEG stream pulls from queue; web UI, `/status`, `/config` served inline). Motion detection uses JPEG file-size diff — no secondary grayscale capture needed, no sensor mode switching.

**Tech Stack:** PlatformIO + Arduino framework for ESP32, `esp_http_server` (ESP-IDF, bundled with Arduino ESP32 core), `esp32-camera` (bundled), FreeRTOS queue for frame handoff.

---

## File Map

| File | Purpose |
|------|---------|
| `firmware-cam/platformio.ini` | Board config, build flags, upload port |
| `firmware-cam/include/credentials.h` | WiFi SSID + password (git-ignored) |
| `firmware-cam/include/credentials.h.example` | Template |
| `firmware-cam/src/camera.h` | Camera init, capture, resolution API |
| `firmware-cam/src/camera.cpp` | OV3660 init with AI-Thinker pinout |
| `firmware-cam/src/motion.h` | JPEG-size-diff motion detection API |
| `firmware-cam/src/motion.cpp` | Motion score, threshold, enable toggle |
| `firmware-cam/src/metrics.h` | FPS counter, frame timing API |
| `firmware-cam/src/metrics.cpp` | Per-second serial log |
| `firmware-cam/src/stream_server.h` | HTTP server start API |
| `firmware-cam/src/stream_server.cpp` | All endpoints + inline web UI HTML |
| `firmware-cam/src/main.cpp` | WiFi init, FreeRTOS tasks, wiring |

---

## Task 1: Scaffold project

**Files:**
- Create: `firmware-cam/platformio.ini`
- Create: `firmware-cam/include/credentials.h.example`
- Create: `firmware-cam/include/credentials.h` (local only, git-ignored)
- Modify: `.gitignore`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p firmware-cam/src firmware-cam/include
```

- [ ] **Step 2: Write `firmware-cam/platformio.ini`**

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

monitor_speed = 115200
upload_speed = 460800
upload_port = /dev/tty.usbserial-21240
monitor_port = /dev/tty.usbserial-21240
```

- [ ] **Step 3: Write `firmware-cam/include/credentials.h.example`**

```cpp
#pragma once
#define WIFI_SSID     "your_wifi_ssid"
#define WIFI_PASSWORD "your_wifi_password"
```

- [ ] **Step 4: Write `firmware-cam/include/credentials.h`** (real creds, never committed)

```cpp
#pragma once
#define WIFI_SSID     "PT MIT"
#define WIFI_PASSWORD "your_actual_password"
```

- [ ] **Step 5: Add to `.gitignore`** (root-level, append)

```
firmware-cam/include/credentials.h
firmware-cam/.pio/
```

- [ ] **Step 6: Write a minimal `firmware-cam/src/main.cpp` so the project compiles**

```cpp
#include <Arduino.h>
void setup() { Serial.begin(115200); }
void loop() {}
```

- [ ] **Step 7: Verify compile**

```bash
cd firmware-cam && pio run
```

Expected: `SUCCESS` with no errors.

- [ ] **Step 8: Commit**

```bash
git add firmware-cam/ .gitignore
git commit -m "feat(esp32cam): scaffold PlatformIO project"
```

---

## Task 2: Camera module

**Files:**
- Create: `firmware-cam/src/camera.h`
- Create: `firmware-cam/src/camera.cpp`

- [ ] **Step 1: Write `firmware-cam/src/camera.h`**

```cpp
#pragma once
#include "esp_camera.h"

namespace camera {
    bool init();
    bool setResolution(int framesize);
    camera_fb_t* capture();
    void returnFrame(camera_fb_t* fb);
}
```

- [ ] **Step 2: Write `firmware-cam/src/camera.cpp`**

```cpp
#include "camera.h"
#include <Arduino.h>

// AI-Thinker ESP32-CAM-MB pinout
#define PWDN_GPIO_NUM   32
#define RESET_GPIO_NUM  -1
#define XCLK_GPIO_NUM    0
#define SIOD_GPIO_NUM   26
#define SIOC_GPIO_NUM   27
#define Y9_GPIO_NUM     35
#define Y8_GPIO_NUM     34
#define Y7_GPIO_NUM     39
#define Y6_GPIO_NUM     36
#define Y5_GPIO_NUM     21
#define Y4_GPIO_NUM     19
#define Y3_GPIO_NUM     18
#define Y2_GPIO_NUM      5
#define VSYNC_GPIO_NUM  25
#define HREF_GPIO_NUM   23
#define PCLK_GPIO_NUM   22

namespace camera {

bool init() {
    camera_config_t config = {};
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer   = LEDC_TIMER_0;
    config.pin_d0       = Y2_GPIO_NUM;
    config.pin_d1       = Y3_GPIO_NUM;
    config.pin_d2       = Y4_GPIO_NUM;
    config.pin_d3       = Y5_GPIO_NUM;
    config.pin_d4       = Y6_GPIO_NUM;
    config.pin_d5       = Y7_GPIO_NUM;
    config.pin_d6       = Y8_GPIO_NUM;
    config.pin_d7       = Y9_GPIO_NUM;
    config.pin_xclk     = XCLK_GPIO_NUM;
    config.pin_pclk     = PCLK_GPIO_NUM;
    config.pin_vsync    = VSYNC_GPIO_NUM;
    config.pin_href     = HREF_GPIO_NUM;
    config.pin_sscb_sda = SIOD_GPIO_NUM;
    config.pin_sscb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn     = PWDN_GPIO_NUM;
    config.pin_reset    = RESET_GPIO_NUM;
    config.xclk_freq_hz = 20000000;
    config.pixel_format = PIXFORMAT_JPEG;
    config.frame_size   = FRAMESIZE_VGA;
    config.jpeg_quality = 12;
    config.fb_count     = 2;
    config.fb_location  = CAMERA_FB_IN_PSRAM;
    config.grab_mode    = CAMERA_GRAB_LATEST;

    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        Serial.printf("[ERROR] Camera init failed: 0x%x\n", err);
        return false;
    }
    return true;
}

bool setResolution(int framesize) {
    sensor_t* s = esp_camera_sensor_get();
    if (!s) return false;
    s->set_framesize(s, (framesize_t)framesize);
    Serial.printf("[CAMERA] resolution -> %d\n", framesize);
    return true;
}

camera_fb_t* capture() {
    return esp_camera_fb_get();
}

void returnFrame(camera_fb_t* fb) {
    esp_camera_fb_return(fb);
}

} // namespace camera
```

- [ ] **Step 3: Update `main.cpp` to call `camera::init()` and print result**

```cpp
#include <Arduino.h>
#include "camera.h"

void setup() {
    Serial.begin(115200);
    delay(1000);
    if (camera::init()) {
        Serial.println("[BOOT] Camera OK");
    } else {
        Serial.println("[BOOT] Camera FAIL");
    }
}
void loop() {}
```

- [ ] **Step 4: Compile**

```bash
cd firmware-cam && pio run
```

Expected: `SUCCESS`.

- [ ] **Step 5: Flash and verify serial**

```bash
pio run -t upload && pio device monitor
```

Expected serial output:
```
[BOOT] Camera OK
```

If you see `Camera init failed: 0x105` — OV3660 not detected. Check that the board is powered (some AI-Thinker boards need 5V not 3.3V on the MB programmer).

- [ ] **Step 6: Commit**

```bash
git add firmware-cam/src/camera.h firmware-cam/src/camera.cpp firmware-cam/src/main.cpp
git commit -m "feat(esp32cam): camera module — OV3660 init with AI-Thinker pinout"
```

---

## Task 3: Metrics module

**Files:**
- Create: `firmware-cam/src/metrics.h`
- Create: `firmware-cam/src/metrics.cpp`

- [ ] **Step 1: Write `firmware-cam/src/metrics.h`**

```cpp
#pragma once
#include <stddef.h>

namespace metrics {
    void onFrame(size_t frameBytes);
    void tick(bool motionDetected);
    int fps();
    int frameMs();
}
```

- [ ] **Step 2: Write `firmware-cam/src/metrics.cpp`**

```cpp
#include "metrics.h"
#include <Arduino.h>

static volatile int _frameCount = 0;
static volatile int _fps = 0;
static volatile int _frameMs = 0;
static unsigned long _lastFrameTime = 0;
static unsigned long _lastTickTime = 0;

namespace metrics {

void onFrame(size_t frameBytes) {
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
```

- [ ] **Step 3: Compile**

```bash
cd firmware-cam && pio run
```

Expected: `SUCCESS`.

- [ ] **Step 4: Commit**

```bash
git add firmware-cam/src/metrics.h firmware-cam/src/metrics.cpp
git commit -m "feat(esp32cam): metrics module — fps, frame timing, serial log"
```

---

## Task 4: Motion detection module

**Files:**
- Create: `firmware-cam/src/motion.h`
- Create: `firmware-cam/src/motion.cpp`

Motion uses JPEG file-size diff as a proxy for scene change. Score = `abs(current_size - prev_size) * 100 / prev_size`. No secondary capture, no sensor mode switching.

- [ ] **Step 1: Write `firmware-cam/src/motion.h`**

```cpp
#pragma once
#include <stddef.h>

namespace motion {
    void init(int threshold = 15);
    void setThreshold(int t);
    void setEnabled(bool e);
    bool isEnabled();
    void checkSize(size_t frameBytes);
    bool detected();
    int  lastScore();
}
```

- [ ] **Step 2: Write `firmware-cam/src/motion.cpp`**

```cpp
#include "motion.h"
#include <Arduino.h>
#include <stdlib.h>

static int    _threshold = 15;
static bool   _enabled   = true;
static bool   _detected  = false;
static int    _lastScore = 0;
static size_t _prevSize  = 0;

namespace motion {

void init(int threshold) {
    _threshold = threshold;
    _enabled   = true;
    _detected  = false;
    _prevSize  = 0;
}

void setThreshold(int t) { _threshold = t; }
void setEnabled(bool e)  { _enabled = e; if (!e) _detected = false; }
bool isEnabled()         { return _enabled; }
bool detected()          { return _detected; }
int  lastScore()         { return _lastScore; }

void checkSize(size_t frameBytes) {
    if (!_enabled || _prevSize == 0) {
        _prevSize = frameBytes;
        return;
    }
    int diff  = abs((int)frameBytes - (int)_prevSize);
    _lastScore = (int)((diff * 100UL) / _prevSize);
    bool prev  = _detected;
    _detected  = (_lastScore > _threshold);
    if (_detected && !prev) {
        Serial.printf("[MOTION] score=%d threshold=%d\n", _lastScore, _threshold);
    }
    _prevSize = frameBytes;
}

} // namespace motion
```

- [ ] **Step 3: Compile**

```bash
cd firmware-cam && pio run
```

Expected: `SUCCESS`.

- [ ] **Step 4: Commit**

```bash
git add firmware-cam/src/motion.h firmware-cam/src/motion.cpp
git commit -m "feat(esp32cam): motion module — JPEG size-diff detection"
```

---

## Task 5: Stream server

**Files:**
- Create: `firmware-cam/src/stream_server.h`
- Create: `firmware-cam/src/stream_server.cpp`

Uses `esp_http_server` (bundled with Arduino ESP32 core). The MJPEG stream handler pulls frames from `frameQueue` (declared extern — defined in `main.cpp`).

- [ ] **Step 1: Write `firmware-cam/src/stream_server.h`**

```cpp
#pragma once
namespace stream_server {
    bool start();
}
```

- [ ] **Step 2: Write `firmware-cam/src/stream_server.cpp`**

```cpp
#include "stream_server.h"
#include "camera.h"
#include "metrics.h"
#include "motion.h"
#include "esp_http_server.h"
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

extern QueueHandle_t frameQueue;

static httpd_handle_t _server = nullptr;

// ---- Web UI (inline HTML) ----
static const char INDEX_HTML[] =
"<!DOCTYPE html><html><head><title>ESP32-CAM</title>"
"<style>body{font-family:monospace;background:#111;color:#0f0;margin:20px}"
"img{max-width:100%;border:1px solid #0f0;display:block;margin-bottom:10px}"
"select,button,input{background:#222;color:#0f0;border:1px solid #0f0;padding:4px 8px;margin:4px}"
".on{color:#f00}.off{color:#0f0}</style></head><body>"
"<h2>ESP32-CAM Test Harness</h2>"
"<img src='/stream'>"
"<div id='s'>Loading...</div>"
"<div>Res:<select id='r'>"
"<option value='0'>QQVGA 160x120</option>"
"<option value='4'>QVGA 320x240</option>"
"<option value='5' selected>VGA 640x480</option>"
"<option value='8'>SVGA 800x600</option>"
"<option value='13'>UXGA 1600x1200</option>"
"</select><button onclick=\"fetch('/config?res='+document.getElementById('r').value)\">Apply</button></div>"
"<div>Motion:<button onclick=\"fetch('/status').then(r=>r.json()).then(d=>fetch('/config?motion='+(d.motion_enabled?0:1)))\">Toggle</button>"
"Threshold:<input type='number' id='t' value='15' min='0' max='100' style='width:50px'>"
"<button onclick=\"fetch('/config?threshold='+document.getElementById('t').value)\">Set</button></div>"
"<script>setInterval(()=>{"
"fetch('/status').then(r=>r.json()).then(d=>{"
"document.getElementById('s').innerHTML="
"'FPS:'+d.fps+' | '+d.frame_ms+'ms | Heap:'+d.heap_kb+'KB | PSRAM:'+d.psram_kb+'KB | Motion:<span class=\"'+(d.motion?'on\">DETECTED':'off\">clear')+'</span>'"
";});},1000);</script></body></html>";

// ---- Handlers ----

static esp_err_t indexHandler(httpd_req_t* req) {
    httpd_resp_set_type(req, "text/html");
    httpd_resp_send(req, INDEX_HTML, (ssize_t)strlen(INDEX_HTML));
    return ESP_OK;
}

static esp_err_t streamHandler(httpd_req_t* req) {
    httpd_resp_set_type(req, "multipart/x-mixed-replace; boundary=--frame");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    httpd_resp_set_hdr(req, "Cache-Control", "no-cache");

    char hdr[64];
    while (true) {
        camera_fb_t* fb = nullptr;
        if (xQueueReceive(frameQueue, &fb, pdMS_TO_TICKS(300)) != pdTRUE || !fb) continue;

        size_t hlen = snprintf(hdr, sizeof(hdr),
            "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %zu\r\n\r\n", fb->len);

        esp_err_t res = httpd_resp_send_chunk(req, hdr, (ssize_t)hlen);
        if (res == ESP_OK) res = httpd_resp_send_chunk(req, (const char*)fb->buf, (ssize_t)fb->len);
        if (res == ESP_OK) res = httpd_resp_send_chunk(req, "\r\n", 2);
        camera::returnFrame(fb);

        if (res != ESP_OK) break;  // client disconnected
    }
    return ESP_OK;
}

static esp_err_t statusHandler(httpd_req_t* req) {
    char json[256];
    snprintf(json, sizeof(json),
        "{\"fps\":%d,\"frame_ms\":%d,\"heap_kb\":%lu,\"psram_kb\":%lu"
        ",\"motion\":%s,\"motion_enabled\":%s,\"motion_score\":%d}",
        metrics::fps(), metrics::frameMs(),
        ESP.getFreeHeap()  / 1024,
        ESP.getFreePsram() / 1024,
        motion::detected()  ? "true" : "false",
        motion::isEnabled() ? "true" : "false",
        motion::lastScore());
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    httpd_resp_send(req, json, (ssize_t)strlen(json));
    return ESP_OK;
}

static esp_err_t configHandler(httpd_req_t* req) {
    char query[128] = {};
    char val[16]    = {};
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
        if (httpd_query_key_value(query, "res",       val, sizeof(val)) == ESP_OK)
            camera::setResolution(atoi(val));
        if (httpd_query_key_value(query, "motion",    val, sizeof(val)) == ESP_OK)
            motion::setEnabled(atoi(val) != 0);
        if (httpd_query_key_value(query, "threshold", val, sizeof(val)) == ESP_OK)
            motion::setThreshold(atoi(val));
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_send(req, "{\"ok\":true}", 11);
    return ESP_OK;
}

// ---- Public ----

namespace stream_server {

bool start() {
    httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
    cfg.server_port     = 80;
    cfg.max_open_sockets = 5;
    cfg.stack_size       = 8192;

    if (httpd_start(&_server, &cfg) != ESP_OK) {
        Serial.println("[ERROR] HTTP server start failed");
        return false;
    }

    const httpd_uri_t uris[] = {
        { "/",       HTTP_GET, indexHandler,  nullptr },
        { "/stream", HTTP_GET, streamHandler, nullptr },
        { "/status", HTTP_GET, statusHandler, nullptr },
        { "/config", HTTP_GET, configHandler, nullptr },
    };
    for (const auto& u : uris) httpd_register_uri_handler(_server, &u);

    Serial.println("[BOOT] HTTP server started on port 80");
    return true;
}

} // namespace stream_server
```

- [ ] **Step 3: Compile**

```bash
cd firmware-cam && pio run
```

Expected: `SUCCESS`. If you see `httpd_req_get_url_query_str` undeclared, add `#include "esp_http_server.h"` — it should already be there.

- [ ] **Step 4: Commit**

```bash
git add firmware-cam/src/stream_server.h firmware-cam/src/stream_server.cpp
git commit -m "feat(esp32cam): stream server — MJPEG, web UI, /status, /config endpoints"
```

---

## Task 6: main.cpp — wire everything together

**Files:**
- Modify: `firmware-cam/src/main.cpp`

- [ ] **Step 1: Rewrite `firmware-cam/src/main.cpp`**

```cpp
#include <Arduino.h>
#include <WiFi.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include "camera.h"
#include "motion.h"
#include "metrics.h"
#include "stream_server.h"
#include "credentials.h"

QueueHandle_t frameQueue;

// Core 0: capture frames, check motion, push to queue
void captureLoop(void*) {
    while (true) {
        camera_fb_t* fb = camera::capture();
        if (fb) {
            metrics::onFrame(fb->len);
            motion::checkSize(fb->len);

            // drop oldest frame if queue full so capture never blocks
            camera_fb_t* old = nullptr;
            if (xQueueReceive(frameQueue, &old, 0) == pdTRUE && old) {
                camera::returnFrame(old);
            }
            xQueueSend(frameQueue, &fb, 0);
        }
        vTaskDelay(1);
    }
}

// Core 1: HTTP server + metrics tick
void serverLoop(void*) {
    stream_server::start();
    while (true) {
        metrics::tick(motion::detected());
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("\n[BOOT] ESP32-CAM firmware starting");

    if (!camera::init()) {
        Serial.println("[ERROR] Camera init failed — halting");
        while (true) delay(1000);
    }
    Serial.println("[BOOT] OV3660 OK");

    motion::init(15);
    frameQueue = xQueueCreate(1, sizeof(camera_fb_t*));

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.print("[BOOT] WiFi connecting");
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.printf("\n[BOOT] IP=%s\n", WiFi.localIP().toString().c_str());

    xTaskCreatePinnedToCore(captureLoop, "capture", 8192, nullptr, 5, nullptr, 0);
    xTaskCreatePinnedToCore(serverLoop,  "server",  8192, nullptr, 3, nullptr, 1);

    Serial.printf("[BOOT] Web UI:    http://%s/\n",      WiFi.localIP().toString().c_str());
    Serial.printf("[BOOT] Stream:    http://%s/stream\n", WiFi.localIP().toString().c_str());
    Serial.printf("[BOOT] Status:    http://%s/status\n", WiFi.localIP().toString().c_str());
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
```

- [ ] **Step 2: Compile**

```bash
cd firmware-cam && pio run
```

Expected: `SUCCESS`.

- [ ] **Step 3: Flash**

```bash
pio run -t upload
```

- [ ] **Step 4: Monitor serial**

```bash
pio device monitor
```

Expected output:
```
[BOOT] ESP32-CAM firmware starting
[BOOT] OV3660 OK
[BOOT] WiFi connecting......
[BOOT] IP=192.168.10.X
[BOOT] HTTP server started on port 80
[BOOT] Web UI:    http://192.168.10.X/
[BOOT] Stream:    http://192.168.10.X/stream
[BOOT] Status:    http://192.168.10.X/status
[METRICS] fps=28 frame_ms=35 heap=142KB psram=3812KB motion=0
```

- [ ] **Step 5: Commit**

```bash
git add firmware-cam/src/main.cpp
git commit -m "feat(esp32cam): main — dual-core tasks, WiFi, FreeRTOS queue wiring"
```

---

## Task 7: Hardware verification

No new files — this task validates the full system on real hardware.

- [ ] **Step 1: Open browser at `http://<IP>/`**

Expected: web UI loads with live MJPEG stream, FPS counter shows ~28 at VGA.

- [ ] **Step 2: Test resolution change**

Select `QQVGA 160x120`, click Apply. Stream restarts at lower resolution. Serial should print:
```
[CAMERA] resolution -> 0
[METRICS] fps=55 frame_ms=18 ...
```

Test each preset. Record actual fps per resolution.

- [ ] **Step 3: Test motion detection**

Wave hand in front of camera. Serial should print:
```
[MOTION] score=28 threshold=15
```

Browser motion indicator should switch to `DETECTED` within 1s (next `/status` poll).

- [ ] **Step 4: Test threshold tuning**

In browser, set threshold to 50, wave hand — motion should NOT trigger. Set to 5 — should trigger on ambient light changes. Find a useful default for your environment.

- [ ] **Step 5: Test motion toggle**

Click Motion Toggle button. Verify `[METRICS]` shows `motion=0` even when waving hand. Toggle back on.

- [ ] **Step 6: Soak test — watch for memory leaks**

Leave running for 5 minutes. Watch `heap` in `[METRICS]`. Should stay stable (±5KB). Drift downward = frame buffer not being returned → look for `camera::returnFrame()` missing calls.

- [ ] **Step 7: Record baseline numbers**

Note fps at each resolution in a comment block at top of `firmware-cam/src/main.cpp`:
```cpp
// Measured fps (OV3660, VGA JPEG quality 12, single WiFi client):
// QQVGA: ~XX fps   QVGA: ~XX fps   VGA: ~XX fps
// SVGA:  ~XX fps   UXGA: ~XX fps
```

- [ ] **Step 8: Final commit**

```bash
git add firmware-cam/src/main.cpp
git commit -m "docs(esp32cam): record measured fps baseline per resolution"
```

---

## Spec Coverage Check

| Spec requirement | Task |
|-----------------|------|
| PlatformIO + Arduino framework | Task 1 |
| `firmware-cam/` directory | Task 1 |
| OV3660 + AI-Thinker pinout | Task 2 |
| Dual-core: Core 0 capture, Core 1 serve | Task 6 |
| 1-slot FreeRTOS queue, drop-on-full | Task 6 |
| Runtime resolution change | Task 2, 5 |
| Motion detection (JPEG size diff) | Task 4 |
| Serial `[METRICS]` every second | Task 3 |
| Serial `[MOTION]` on detection | Task 4 |
| MJPEG stream on port 80 `/stream` | Task 5 |
| Web UI inline HTML | Task 5 |
| `/status` JSON endpoint | Task 5 |
| `/config` endpoint (res, motion, threshold) | Task 5 |
| FPS counter + frame_ms in UI | Task 3, 5 |
| Motion indicator in UI | Task 4, 5 |
| Heap + PSRAM in metrics | Task 3 |
| Hardware verification | Task 7 |
