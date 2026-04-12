# 19 — SD Card Storage

What lives on the MicroSD card, why, and how it's organized.

---

## Overview

The SD card is Aksa's local persistence layer — it bridges the gap between the backend (source of truth) and the ESP32's limited internal storage. It enables offline resilience, response-speed optimizations, and richer display/audio assets without hammering the API on every interaction.

---

## Directory layout

```
/
├── audio/
│   ├── cache/          ← TTS Opus cache (SHA-256 keyed, LRU 100MB cap)
│   ├── resilience/     ← Fallback clips preloaded to PSRAM on boot
│   ├── ui/             ← Sound effects and chimes (streamed on demand)
│   └── buffer/         ← WebSocket disconnect recording buffer
├── display/
│   ├── sprites/        ← Face expression sprite sheets (future)
│   ├── fonts/          ← Custom TFT bitmap fonts (future)
│   └── icons/          ← Display mode icons (clock, pomodoro, etc.)
├── ota/                ← OTA firmware staging area before flash
├── config/
│   └── device.json     ← Full config snapshot from backend (offline fallback)
├── queue/
│   └── events.json     ← Outbound event queue when Wi-Fi is down
└── logs/
    └── debug.log       ← Rolling debug log, 1MB rotation
```

---

## What's stored and why

### Audio cache (`/audio/cache/`)

TTS responses are encoded as Opus and cached here with a SHA-256 key derived from the text + voice preset. On a cache hit the backend skips ElevenLabs and returns the cached audio directly, cutting response latency and API cost. LRU eviction keeps total usage under 100MB.

**Already implemented** in `tts_cache_manager`.

---

### Resilience audio (`/audio/resilience/`)

Short fallback Opus clips loaded into PSRAM at boot. Played when the backend is unreachable or a pipeline stage fails. No SD read latency since they live in RAM.

| File | When played |
|------|-------------|
| `offline.opus` | Wi-Fi lost / backend unreachable |
| `error.opus` | Unrecoverable pipeline error |
| `stt_fail.opus` | Speech not understood |
| `boot.opus` | Startup complete |
| `thinking.opus` | LLM taking too long |
| `sleep.opus` | Entering sleep mode |
| `wake.opus` | Waking from sleep |

**Already implemented** in `resilience_audio`.

---

### UI audio (`/audio/ui/`)

Short sound effects streamed directly from SD on demand. No PSRAM preloading needed — these are triggered by events, not latency-sensitive pipeline stages. See `17-audio-assets.md` for the full clip list.

Examples: pomodoro ding, focus mode start/end chime, reminder ping, presence arrival tone.

---

### Recording buffer (`/audio/buffer/`)

When the WebSocket disconnects mid-recording, the audio capture loop writes chunks here instead of dropping them. On reconnect, the firmware replays the buffer with `audio:start{buffered:true}` so the conversation isn't lost.

**Already implemented** in `recording_buffer`.

---

### OTA staging (`/ota/`)

Firmware updates are downloaded here before flashing. SHA-256 verified before `esp_ota_begin` is called. Allows atomic update with rollback if verification fails.

**Already implemented** in `ota_update` (flash step is a hardware TODO).

---

### Config snapshot (`/config/device.json`)

A full copy of the device's backend config written to SD after every successful `config:update` WebSocket event. If the ESP32 boots without Wi-Fi or the backend is unreachable, it reads from here instead of using compile-time defaults.

**Why it matters:** NVS only stores primitive values (strings/ints). Complex settings (voice preset, idle config, BLE thresholds) currently live only in backend or RAM — this gives them a persistent local fallback.

**Not yet implemented.**

---

### Offline event queue (`/queue/events.json`)

When Wi-Fi is down, outbound events that would normally go to the backend are queued here as JSON lines. On reconnect, the firmware drains the queue in order before resuming live events.

Candidates for queuing:
- `presence:arrived` / `presence:departed`
- `device:info` (firmware version, RSSI report)
- Any interaction counters for analytics

**Not yet implemented.**

---

### Display assets (`/display/`)

See the [Face sprite sheets](#face-sprite-sheets) section below for detail.

---

### Debug log (`/logs/debug.log`)

Rolling log written by `LOG_I` / `LOG_W` / `LOG_E` macros across all modules. Rotated at 1MB. Useful for post-mortem debugging without serial monitor.

**Already implemented** in `debug_logging`.

---

## Face sprite sheets

The current face renderer draws everything procedurally in C++ — circles, arcs, and lines calculated at runtime each frame. This works well for the simulator and keeps firmware self-contained, but has limits:

- Expressions are constrained to what geometry can express
- Smooth complex animations (blinking with lid curl, squint gradients) are expensive to compute
- Swapping the visual style requires rewriting C++ drawing code

### What a sprite sheet approach gives you

A sprite sheet is a single PNG/BMP image containing all animation frames tiled in a grid. The firmware reads the sheet once from SD into PSRAM, then blits individual frames to the display by index — no per-frame computation.

```
sprite_sheet.bmp
┌─────────────────────────────────┐
│ [idle_0][idle_1][idle_2][idle_3]│  ← idle blink cycle (4 frames)
│ [hap_0][hap_1][hap_2][hap_3]   │  ← happy expression
│ [sad_0][sad_1][sad_2][sad_3]    │  ← sad expression
│ [think_0][think_1]...           │  ← thinking dots
│ ...                             │
└─────────────────────────────────┘
```

Each frame is a fixed tile size (e.g. 128×128 px for a 2.8" 240×320 display). The firmware stores frame coordinates in a lookup table and calls `tft.pushImage(x, y, w, h, frame_ptr)`.

### Display constraints (2.8" IPS, 240×320)

| Parameter | Value |
|-----------|-------|
| Resolution | 240 × 320 px |
| Face area | ~200 × 200 px (leaving room for status bar) |
| Reasonable frame size | 128 × 128 px (centered, some margin) |
| Color depth | 16-bit RGB565 (2 bytes/px) |
| Single frame RAM | 128 × 128 × 2 = 32KB |
| 10 frames in PSRAM | 320KB — easily fits in 8MB PSRAM |

### Storage estimate

| Expression set | Frames | Size (128×128 RGB565) |
|---------------|--------|-----------------------|
| Idle blink cycle | 6 | 192KB |
| Happy | 4 | 128KB |
| Sad | 4 | 128KB |
| Listening | 4 | 128KB |
| Thinking | 6 | 192KB |
| Speaking (mouth states) | 6 | 192KB |
| Sleeping | 4 | 128KB |
| Confused / Shrug | 4 | 128KB |
| **Total** | **~38 frames** | **~1.2MB** |

1.2MB fits comfortably on any SD card and in a single SPI read at boot.

### How the firmware would use it

1. At boot, `display_manager` reads `sprite_sheet.bmp` from SD into a PSRAM buffer
2. A `SpriteSheet` struct holds frame metadata (tile x/y, width, height, frame count per expression)
3. The face animation loop calls `blitFrame(expression, frame_index)` instead of the current `drawEye()` / `drawMouth()` functions
4. Talking mouth states are driven by audio amplitude the same way as now — but mapped to a frame index instead of a computed arc

### How to create the sheet

The sprite art can be made in any pixel editor (Aseprite is the standard for this). Export as BMP (RGB565 raw) or convert with ImageMagick:

```bash
magick sprite_sheet.png -type TrueColor -define bmp:subtype=RGB565 sprite_sheet.bmp
```

The procedural renderer stays as a fallback if no `sprite_sheet.bmp` is found on SD — so you can ship firmware without it and add it later.

### Trade-offs

| | Procedural (current) | Sprite sheet |
|---|---|---|
| Visual style | Geometric, flat | Anything — pixel art, illustrated |
| Firmware complexity | High (drawing logic) | Low (blit by index) |
| Customization | Recompile required | Swap BMP on SD card |
| RAM usage | Near zero | ~1–2MB PSRAM |
| Frame computation | Per frame | Zero (precomputed) |
| Animation smoothness | Limited by CPU | Limited by frame count |

The sprite sheet approach is the better long-term path once you settle on the visual style — it decouples art from firmware entirely.

---

## Recommended SD card spec

| Requirement | Recommendation |
|-------------|---------------|
| Capacity | 4GB minimum, 16GB comfortable |
| Speed class | Class 10 / U1 (10MB/s) minimum for smooth audio streaming |
| Interface | SDIO 4-bit (already wired on the ES3C28P board) |
| Format | FAT32 |

A 16GB Class 10 card gives ~15GB usable headroom for TTS cache growth, logs, and display assets.
