# ESP32-CAM Custom Firmware — Design Spec

**Date:** 2026-04-23  
**Board:** AI-Thinker ESP32-CAM-MB (OV3660, 4MB flash, PSRAM)  
**Goal:** Replace Tasmota with custom C++ firmware. Test harness to measure fps/latency, motion detection, and image quality at different resolutions. Future integration with aksabot backend possible if results are good.

---

## 1. Repository Location

```
firmware-cam/          — sibling to firmware/ (ESP32-S3 aksabot firmware)
  platformio.ini
  src/
    main.cpp
    camera.cpp / camera.h
    motion.cpp / motion.h
    stream_server.cpp / stream_server.h
    metrics.cpp / metrics.h
```

Separate PlatformIO project. Same toolchain as aksabot firmware (PlatformIO + Arduino framework).

---

## 2. Architecture

### Dual-core FreeRTOS

| Task | Core | Stack | Purpose |
|------|------|-------|---------|
| `captureLoop` | 0 | 8KB | Camera grab → motion check → push to queue |
| `serverLoop` | 1 | 8KB | HTTP server: MJPEG stream + web UI + config API |

**Frame queue:** 2-slot FreeRTOS queue between cores. Core 0 drops oldest frame if queue is full — capture never blocks waiting for the server. This isolates capture throughput from network throughput so each can be measured independently.

### Module responsibilities

| Module | Responsibility |
|--------|---------------|
| `camera` | OV3660 init (AI-Thinker pinout), frame capture, PSRAM frame buffers, runtime resolution change |
| `motion` | Frame-diff motion detection using secondary grayscale capture, configurable threshold |
| `stream_server` | HTTP server, MJPEG endpoint, inline web UI, `/status` JSON, `/config` API |
| `metrics` | Per-second serial log: fps, frame_ms, heap, PSRAM, motion state |

---

## 3. Camera

**Init config:**
- PSRAM enabled — all frame buffers allocated in PSRAM, not internal heap
- Default: VGA 640×480, JPEG quality 12
- AI-Thinker GPIO pinout hardcoded (PWDN=32, RESET=-1, XCLK=0, SDA=26, SCL=27, D7..D0, VSYNC=25, HREF=23, PCLK=22)

**Resolution presets (runtime selectable):**

| Index | Size | Target fps |
|-------|------|-----------|
| 0 | QQVGA 160×120 | ~60 fps |
| 4 | QVGA 320×240 | ~45 fps |
| 5 | VGA 640×480 | ~30 fps |
| 8 | SVGA 800×600 | ~15 fps |
| 13 | UXGA 1600×1200 | ~5 fps |

Resolution change reinitializes the camera sensor — brief stream stutter expected.

---

## 4. Motion Detection

Uses a **secondary grayscale capture** at low resolution (QQVGA) alongside the main JPEG stream. No JPEG decode needed — grayscale pixels are compared directly.

**Algorithm:**
1. Capture QQVGA grayscale frame on Core 0 (separate `esp_camera_fb_get` call)
2. Pixel-diff against previous grayscale frame: `score = sum(|curr[i] - prev[i]|) / pixel_count`
3. If `score > threshold` → motion detected
4. Log to serial: `[MOTION] score=42 threshold=15`
5. Update shared atomic flag read by `/status` endpoint

**Config:**
- Threshold: 0–100, default 15
- Toggle on/off at runtime via `/config?motion=0|1`

Motion detection runs every frame on Core 0 before pushing to queue. Grayscale capture is fast (~2ms at QQVGA) — negligible impact on main stream fps.

---

## 5. HTTP Server & Web UI

**Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | Inline HTML web UI |
| `/stream` | GET | MJPEG stream (multipart/x-mixed-replace) |
| `/status` | GET | JSON: `{fps, frame_ms, heap, psram, motion}` |
| `/config` | GET | Set params: `?res=5&motion=1&threshold=20` |

All on port 80. No port 81 (unlike Tasmota).

**MJPEG stream:** Standard multipart boundary format. Server pulls frame from queue, writes `--boundary\r\nContent-Type: image/jpeg\r\nContent-Length: N\r\n\r\n` + JPEG bytes, releases frame buffer back to camera driver.

**Web UI** (inline string in `stream_server.cpp`):
```
┌─────────────────────────────────┐
│  ESP32-CAM Test Harness         │
│  IP: 192.168.10.23              │
├─────────────────────────────────┤
│  [live MJPEG stream]            │
├─────────────────────────────────┤
│  Resolution: [VGA▼]   [Apply]  │
│  Motion: [ON]  Threshold: [15] │
│                                 │
│  FPS: 28   Frame: 35ms          │
│  Heap: 142KB   PSRAM: 3.8MB    │
│  Motion: ● DETECTED / ○ clear  │
└─────────────────────────────────┘
```

FPS + motion status auto-refresh every 1s via `fetch('/status')`. No WebSocket — polling is sufficient for a test harness.

---

## 6. Serial Metrics

Logged every second from `metrics` module:

```
[METRICS] fps=28 frame_ms=35 heap=142KB psram=3812KB motion=0
[MOTION] score=42 threshold=15
[CAMERA] res changed to VGA (5)
[BOOT] OV3660 init OK, PSRAM=4MB, IP=192.168.10.23
```

Tags: `[BOOT]`, `[METRICS]`, `[MOTION]`, `[CAMERA]`, `[ERROR]`.

---

## 7. PlatformIO Config

```ini
[env:esp32cam]
platform = espressif32
board = esp32cam
framework = arduino

board_build.flash_size = 4MB
board_build.partitions = huge_app.csv   ; maximize app partition, no OTA

build_flags =
    -DBOARD_HAS_PSRAM
    -DCORE_DEBUG_LEVEL=0

monitor_speed = 115200

lib_deps =
    ; esp32-camera is bundled with the ESP32 Arduino core — no extra lib_dep needed
```

No extra libraries needed — `esp32-camera` ships with the ESP32 Arduino core.

---

## 8. What This Tests

| Dimension | How measured |
|-----------|-------------|
| Raw fps | `[METRICS]` serial log per resolution |
| Frame latency | `frame_ms` in metrics — time from `fb_get` to queue push |
| Capture vs serve bottleneck | If queue is always full → server is bottleneck; if queue empty → capture is bottleneck |
| Motion detection accuracy | Manual observation: wave hand, check score vs threshold |
| Image quality | Visual inspection in browser at each resolution |
| Memory pressure | `heap` + `psram` in metrics — watch for leaks over time |

---

## 9. Out of Scope

- Backend WebSocket integration (future, pending test results)
- OTA updates
- Authentication on web UI
- RTSP (MJPEG sufficient for testing)
- SD card (not on AI-Thinker ESP32-CAM-MB without GPIO conflicts)

---

## Related

- `esp32cam-handoff.md` — hardware spec, flash command, network info
- `firmware/` — aksabot ESP32-S3 firmware (same toolchain pattern)
- `docs/11-future-extensions.md` — camera/vision extension context
