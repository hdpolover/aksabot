# 05 — ESP32 Firmware

---

## Overview

The ESP32-S3 firmware handles all hardware interaction: audio capture/playback, display rendering, touch input, BLE services, and WebSocket communication. It does NOT perform any AI processing.

**Framework:** ESP-IDF / Arduino with PlatformIO
**Board:** Hosyond ESP32-S3 N16R8 (16MB flash, 8MB PSRAM, 2.8" IPS touch)

---

## Core modules

### 1. Audio I/O (I2S)

| Component | Config |
|-----------|--------|
| Microphone | I2S input, 16kHz sample rate, 16-bit mono |
| Speaker | I2S output, matches TTS output format |
| Buffer size | Small ring buffer -- never store full audio in memory |

**Key constraint:** ESP32-S3 has limited RAM. Audio must be streamed in chunks, never buffered entirely. Opus encoding helps here -- each 20ms frame is only ~60-120 bytes.

### 2. Opus codec

- Encode mic audio to Opus before sending over WebSocket
- Decode received Opus audio before playing through speaker
- Library: `libopus` compiled as ESP-IDF component
- Frame size: 20ms (320 samples at 16kHz)
- Target bitrate: 16-24 kbps (speech-optimized)

### 3. WebSocket client

- Library: `esp_websocket_client`
- Connection: `wss://backend-url/ws` with `Authorization: DeviceToken <token>` header
- Sends: `audio:start`, `audio:chunk` (binary), `audio:end`
- Receives: `response:start`, `response:chunk` (binary), `response:end`, `state:update`, `error`
- Auto-reconnect with exponential backoff on disconnect

### 4. Wi-Fi

- Phase 1: Hardcoded credentials for development
- Phase 4+: Credentials received via BLE provisioning, stored in NVS flash
- Connection monitoring: notify display of Wi-Fi status changes
- Reconnect logic with exponential backoff

### 5. BLE services

Four GATT services for Flutter app communication, plus BLE presence scanning. See [08-ble-provisioning.md](08-ble-provisioning.md) for provisioning details and [12-features.md](12-features.md) for presence detection details.

**GATT server (for Flutter app provisioning/control):**
- Wi-Fi provisioning (0xFFE0)
- Device auth (0xFFE1)
- Device control (0xFFE2)
- Device status (0xFFE3)

**BLE scanner (for presence detection):**
- Scans for the Flutter app's presence advertising UUID (0xFFE4)
- Passive scan every 5s for 2s (40% duty cycle)
- RSSI smoothing: rolling average of last 5 readings
- Drives the presence state machine: PRESENT → LEAVING → AWAY → PRESENT
- On AWAY → PRESENT transition: triggers wake + greeting flow
- See [12-features.md](12-features.md) for the full state machine and RSSI thresholds

### 6. NVS storage

Non-volatile storage for persistent config (small key-value pairs):

| Key | Type | Description |
|-----|------|-------------|
| wifi_ssid | string | Wi-Fi network name |
| wifi_pass | string | Wi-Fi password |
| device_token | string | Backend auth token |
| volume | uint8 | Speaker volume (0-100) |
| brightness | uint8 | Display brightness (0-100) |
| presence_en | uint8 | BLE presence detection enabled (0/1) |
| presence_rssi | int8 | RSSI threshold for "present" (default -75) |
| presence_grace | uint16 | Grace period in seconds before AWAY (default 45) |

### 7. MicroSD storage

The MicroSD slot is used for larger data that doesn't fit in NVS: cached audio files, pre-loaded resilience audio, OTA firmware staging, recording buffer, and debug logs.

**Interface:** SPI (shares bus with display, separate CS pin)
**Filesystem:** FAT32 via ESP-IDF `esp_vfs_fat` + `sdmmc`
**Typical card:** 4-16 GB (more than enough — total usage is likely < 500 MB)

#### Directory structure

```
/sdcard/
  cache/
    tts/
      <hash>.opus          -- cached TTS audio files (keyed by text+language hash)
      manifest.json        -- index: { hash, text_preview, size, created_at, last_used, hit_count }
  audio/
    resilience/
      offline.opus         -- "I'm having trouble connecting."
      error.opus           -- "Something went wrong on my end."
      stt_fail.opus        -- "I didn't catch that. Could you try again?"
      boot.opus            -- boot-up chime / greeting
      ota.opus             -- "I'm updating. Please wait."
      thinking.opus        -- optional: short "hmm" sound for thinking state
    buffer/
      pending_XXXXXX.opus  -- recording buffer (if WebSocket drops mid-recording)
  ota/
    firmware.bin           -- staged firmware binary (downloaded before flashing)
  logs/
    debug.log              -- rolling debug log (capped at 1 MB, oldest entries pruned)
```

#### TTS audio cache (local)

The biggest win. The backend includes cache hints with audio responses so the ESP32 knows what to cache locally.

**How it works:**

```
1. Backend sends response:chunk with Opus audio
2. Backend sends response:end with { fullText, cacheKeys: [{ hash, sentence }...] }
3. ESP32 saves each sentence's Opus audio to /sdcard/cache/tts/<hash>.opus
4. Updates manifest.json with metadata

Next time the same response is needed:
1. Backend sends response:start with { cacheKeys: [{ hash, sentence }...] }
2. ESP32 checks local cache for each hash
3. Cache HIT  → play from SD card instantly (zero network latency for that sentence)
4. Cache MISS → wait for response:chunk from backend as normal
```

**Cache management:**
- Max cache size: configurable (default 100 MB)
- Eviction: LRU — when cache exceeds max size, delete least-recently-used entries
- The manifest tracks `hit_count` and `last_used` per entry for smart eviction
- Backend can send a `cache:invalidate` event to clear specific entries (e.g., if voice/language changes)

**What gets cached effectively:**
- Greetings ("Good morning, Hendra", "Hi there")
- Common error responses ("I didn't understand that", "Could you repeat that?")
- Frequently asked questions that get similar answers
- Short acknowledgments ("Sure", "Got it", "Let me think about that")

**What doesn't cache well:**
- Long unique responses (each conversation is different)
- Responses with dynamic data (weather, time, dates)

#### Resilience audio (pre-loaded)

Pre-loaded audio files that the bot can play without any network connection. These are generated once (via TTS during setup or manually) and shipped with the firmware or downloaded on first provisioning.

| File | When played | Fallback if missing |
|------|------------|-------------------|
| offline.opus | WebSocket disconnected, Wi-Fi down | Show offline face silently |
| error.opus | Backend returns an error | Show error face silently |
| stt_fail.opus | Empty STT transcript | Show confused face silently |
| boot.opus | Device powers on | No sound on boot |
| ota.opus | OTA update started | Show update screen silently |
| thinking.opus | Optional: play during thinking state for long waits | Silence (face animation only) |

These files are small (~5-20 KB each in Opus) and loaded into the `/sdcard/audio/resilience/` directory.

#### Recording buffer (network resilience)

If the WebSocket connection drops while the user is speaking mid-recording:

```
1. User is speaking → audio:chunk being sent over WebSocket
2. WebSocket disconnects mid-stream
3. ESP32 detects disconnect → starts writing remaining audio to /sdcard/audio/buffer/
4. ESP32 shows offline face, continues recording until user releases
5. WebSocket reconnects (auto-reconnect with backoff)
6. ESP32 re-sends buffered audio: audio:start → chunks from buffer → audio:end
7. Delete buffer file after successful send
8. Pipeline continues normally
```

This is NOT the "offline message queueing" we excluded — we're not queueing multiple conversations. This is a safety net for a single recording interrupted by a brief network hiccup. The buffer is at most one recording (~30 seconds of Opus = ~90 KB).

#### OTA firmware staging

Safer than streaming firmware directly to flash:

```
1. Backend sends OTA notification with firmware URL and checksum
2. ESP32 downloads firmware.bin to /sdcard/ota/firmware.bin
3. ESP32 verifies checksum (SHA-256)
4. If checksum matches → flash from SD card to OTA partition
5. If download fails or checksum mismatch → delete file, report error, no bricking risk
6. Delete firmware.bin after successful flash
```

This means a failed download doesn't leave the device in a half-flashed state.

#### Debug logs

Rolling log file for development and troubleshooting:

- Written to `/sdcard/logs/debug.log`
- Max size: 1 MB (oldest lines pruned when exceeded)
- Logs: heap free size, Wi-Fi events, WebSocket events, audio pipeline timing, errors
- Retrievable via BLE (future: add a log dump characteristic) or by physically removing the SD card
- Disabled in production builds to reduce SD card wear

---

## Display system

### Hardware

- 2.8" IPS TFT (320x240), likely ST7789 or ILI9341 driver
- Capacitive touch overlay
- SPI interface

### Face animation

The bot's "face" is a set of animated expressions rendered on the TFT. Each expression is a state in a simple state machine.

| Expression | When shown | Animation |
|------------|-----------|-----------|
| Idle/happy | Default state | Eyes open, occasional blinking (random interval 3-8s) |
| Listening | Touch-to-talk active | Eyes wide, pulsing indicator |
| Thinking | Waiting for backend response | Eyes looking around, loading dots |
| Speaking | Playing audio response | Mouth animation synced to audio amplitude |
| Confused | Error or didn't understand | Tilted eyes, question mark |
| Sleeping | After idle timeout | Eyes closed, gentle breathing animation |
| Offline | No backend connection | Greyed out face, Wi-Fi icon with X |
| Encouraging | Stand up / stretch reminder | Cheerful eyes, upward expression |
| Calm | Eye break / focus mode | Soft eyes, relaxed expression |
| Focused | During pomodoro focus phase | Determined eyes, slight squint |

### Display modes

The screen supports multiple display modes beyond just the face. Mode switching is driven by backend events and user interaction.

| Mode | Layout | Trigger |
|------|--------|---------|
| **Face** (default) | Full-screen animated face + status bar | Default, voice command "show face", tap during other modes |
| **Clock** | Large time (center), date (below), next reminder (bottom), mini face (corner) | Voice command "show clock", auto after configurable idle timeout |
| **Pomodoro** | Phase label "FOCUS"/"BREAK" (top), large countdown (center), cycle dots (bottom) | `proactive:pomodoro` event from backend |
| **Reminder** | Reminder icon (top), text (center), "tap to dismiss" (bottom) | `proactive:reminder` event, auto-returns after duration |
| **Countdown** | Large countdown number (center), instruction text (below) | Eye break reminder (20s countdown) |
| **Status** | Wi-Fi, battery, uptime, conversations today, cache stats | Voice command "show status" |

Mode transitions:

```
[idle timeout] ──────────> clock mode
[proactive:reminder] ────> reminder mode ──[durationMs]──> previous mode
[proactive:pomodoro] ────> pomodoro mode ──[stop]────────> face mode
[user tap] ──────────────> face mode (from any mode)
[voice: "show clock"] ───> clock mode
[voice: "show face"] ────> face mode
```

### Transcript display mode

Toggleable overlay (works on top of any display mode) that shows:
- What the bot heard (user transcript from STT)
- What the bot is saying (response text)

Useful for debugging and for environments where audio isn't ideal. Toggled via device settings.

### Status bar

Small status indicators at top of screen (visible in face and clock modes):
- Wi-Fi signal strength (icon)
- Battery level (if on battery)
- Current state text (optional)
- Focus mode indicator (when active)
- Pomodoro cycle indicator (when active)

---

## Touch interaction

### Touch-to-talk

Primary interaction model:
1. User taps and holds screen -> starts recording (mic active, face switches to "listening")
2. User releases -> stops recording, sends `audio:end` (face switches to "thinking")
3. Backend responds -> audio plays (face switches to "speaking")
4. Audio finishes -> face returns to "idle"

### Wake from sleep

- Touch anywhere on screen wakes from sleep mode
- Face transitions from "sleeping" to "idle" animation

---

## Power management

| State | Display | Audio | Wi-Fi | BLE | Trigger |
|-------|---------|-------|-------|-----|---------|
| Active | Full brightness | On | Connected | Scan 5s interval | User interaction, presence PRESENT |
| Dim | Reduced brightness | Off | Connected | Scan 5s interval | Idle for N seconds (configurable) |
| Sleep (idle) | Off | Off | Connected (low power) | Scan 5s interval | Idle for N minutes |
| Sleep (away) | Off | Off | Connected (low power) | Scan 30s interval | BLE presence → AWAY |
| Wake | Full brightness | On | Connected | Scan 5s interval | Touch event OR BLE presence → PRESENT |

**Sleep triggers (two paths):**
1. **Idle timeout** — no interaction for N minutes, user is still present (phone detected). Light sleep, wakes on touch.
2. **BLE presence AWAY** — phone signal lost for grace period. Deeper sleep with reduced BLE scan frequency (30s instead of 5s). Wakes automatically when phone returns.

**Note:** Wi-Fi stays connected in both sleep states to maintain WebSocket heartbeat. Full deep sleep with Wi-Fi off is not used — reconnection time is too slow for a desk companion.

---

## Firmware tasks (FreeRTOS)

| Task | Priority | Core | Description |
|------|----------|------|-------------|
| audio_capture | High | 0 | I2S mic read + Opus encode |
| audio_playback | High | 0 | Opus decode + I2S speaker write (checks SD cache before network) |
| websocket | Medium | 1 | WebSocket send/receive |
| display | Medium | 1 | Face rendering and animation |
| ble | Low | 1 | BLE GATT server + presence scanner |
| touch | Medium | 1 | Touch input processing |
| sd_cache | Low | 1 | Background TTS cache writes, buffer cleanup, log flush |

ESP32-S3 has dual cores -- audio tasks run on core 0, everything else on core 1 to avoid audio glitches. SD card writes are low priority and happen after audio playback starts, never blocking it.

---

## Phase 1 deliverables (weeks 1-3)

1. PlatformIO project setup with ESP-IDF
2. I2S mic input working (16kHz, 16-bit mono)
3. I2S speaker output working
4. Opus encode/decode integrated
5. Wi-Fi connection (hardcoded credentials)
6. WebSocket client with device token auth
7. Stream Opus audio to backend, receive and play response
8. MicroSD initialized with FAT32, directory structure created

## Phase 2 deliverables (weeks 4-5)

1. TFT display driver initialized
2. Face animation state machine (all 7 expressions)
3. Touch-to-talk implemented
4. Status bar with Wi-Fi indicator
5. Transcript display mode
6. Sleep/wake on touch
7. Offline face expression
8. Resilience audio files loaded and playable from SD card (offline, error, boot)
9. Recording buffer to SD card on WebSocket disconnect

## Phase 5 deliverables (weeks 12-14)

1. Local TTS cache: save/lookup/play cached audio from SD card
2. Cache manifest management (LRU eviction, size limits)
3. OTA firmware staging via SD card
4. Debug logging to SD card (dev builds)

---

## GPIO pin budget

Current allocation for V1. See [11-future-extensions.md](11-future-extensions.md) for how extensions (servos, motors, sensors) fit into the remaining budget.

```
V1 allocated:
  I2S mic:       3 pins (BCLK, WS, DATA)
  I2S speaker:   3 pins (BCLK, WS, DATA) — may share clock with mic
  SPI display:   4 pins (CLK, MOSI, DC, CS) + 1 backlight
  SPI touch:     1 pin (CS, shares SPI bus with display)
  SPI MicroSD:   1 pin (CS, shares SPI bus with display)
  ─────────────────
  Total V1:      ~13 pins of ~45 available

Reserved for future:
  Servos:        2-3 PWM pins (Extension 1: expressive movement)
  Motor driver:  4 pins (Extension 2: mobility)
  Cliff sensors: 3 analog pins (Extension 2)
  I2C bus:       2 pins shared (ToF sensor, IMU — Extension 2)
```

**Note on SPI bus sharing:** The display, touch, and MicroSD all share the same SPI bus (HSPI) with separate CS pins. This means only one can be active at a time. SD card access must be scheduled to avoid conflicting with display updates. In practice this is fine — SD writes happen in a low-priority background task and the SPI transactions are fast (~1ms per block).

---

## Related docs

- [04-audio-pipeline.md](04-audio-pipeline.md) — Audio encoding details and WebSocket protocol
- [08-ble-provisioning.md](08-ble-provisioning.md) — BLE GATT service specifications
- [11-future-extensions.md](11-future-extensions.md) — Servo movement, mobility, and other post-V1 hardware extensions
