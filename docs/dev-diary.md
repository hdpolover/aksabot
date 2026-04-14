# Aksabot Development Diary

> A personal log of building an AI desk companion from scratch — firmware, backend, mobile app, and everything in between. Written for a future blog post.

---

## The Idea

I wanted a physical thing on my desk that could talk to me. Not just a smart speaker I bought — something I built, something that felt like *mine*. An ESP32 with a face on its touchscreen, voice input and output, a persistent memory of who I am and what I care about, and a companion Flutter app to manage it all.

I called it **Aksabot** and the bot's name is **Aksa**.

The stack: ESP32-S3 firmware (C++/PlatformIO), NestJS backend, Gemini AI, ElevenLabs TTS, Flutter companion app, deployed on a VPS with Dokploy.

Total time so far: **7 days, 216 commits.**

---

## Day 1 — April 9: Foundation Sprint

### What happened

I sat down and wrote the entire backend in one session. NestJS with PostgreSQL and Redis. Six database tables: users, devices, conversations, messages, memories, response\_pool. Auth with JWT and separate device tokens (the ESP32 speaks WebSocket, not HTTP sessions). The AI pipeline as three decoupled stages — STT → LLM → TTS — each behind an interface so I can swap providers without touching anything else.

By the end of the night: register user → create device → connect WebSocket → send audio → receive TTS response. Working. On the first day.

### Key decisions made

**Decoupled AI pipeline, not Gemini multimodal live.** I could have used Gemini's multimodal live API and done everything in one call. I didn't. A single API call is a black box — you can't see the transcript, can't cache TTS, can't swap one stage independently. Three interfaces, three adapters, three points of observability. The latency cost (~300ms overhead) was worth it.

**Raw `ws` over Socket.IO.** The ESP32's WebSocket library speaks standard WebSocket. Socket.IO adds a protocol layer on top that the firmware can't handle. This meant using `@nestjs/platform-ws` on the backend instead of the default Socket.IO — a less documented path, but the right one.

**TypeORM not Prisma.** Simpler for this project. No schema-first dance, migrations are just TypeScript files, and the entity-based model maps cleanly to how I think about the data.

### Bug of the day

The response pool (pre-generated bot messages for reminders, greetings) was set to fill itself immediately on device connect. Consequence: every time I tested a connection, it hit Gemini and generated 20 responses. I burned through API quota in two test runs. Fixed it to lazy-fill during idle time only.

---

## Day 2 — April 10: The Flutter App + Hardware Arrives

### What happened

Bootstrapped the Flutter app with clean architecture, BLoC, GoRouter, and wired up all the core screens: auth, device list, device detail, conversations, memories, settings. Also scaffolded the entire ESP32 firmware with placeholder modules — 25 .cpp files, all the includes, the FreeRTOS task structure.

Then the hardware arrived. An **ES3C28P** board — ESP32-S3 N16R8 (16MB flash, 8MB PSRAM), 2.8" IPS touchscreen, built-in mic and speaker, MicroSD slot, USB-C, battery charging. Bought it from a local electronics marketplace for ~Rp 435,600 (~$27).

I flashed it. It booted. The display worked. Touch worked. Wi-Fi connected. WebSocket connected to my backend.

But text rendering was completely broken.

### The TFT_eSPI text bug

TFT_eSPI is the standard ESP32 display library. Shapes — rectangles, circles, lines — rendered perfectly. Text was garbage. Corrupted pixels, wrong characters, unreadable. I spent hours debugging font configs, SPI frequency, DMA settings. Nothing worked.

**Root cause:** This specific board (ES3C28P, ILI9341V variant) has something subtly different in its SPI timing or display controller initialization that breaks TFT_eSPI's text rendering on ESP32-S3.

**Fix:** Switched to **LovyanGFX**, a more modern and actively maintained display library with better ESP32-S3 support. Immediately worked. Also discovered I needed `invertDisplay(true)` — without it, black was white and white was black.

### Other hardware discoveries

- **PSRAM type matters**: The board uses `dio_opi` PSRAM, not `qio_opi`. Wrong setting → crash on boot. No error message, just a boot loop.
- **Custom partitions fail silently**: My `partitions.csv` caused a boot loop. Had to use the stock `default_16MB.csv`.
- **I2C shared bus**: Touch IC (FT6336G) and audio codec (ES8311) share GPIO 15/16. Touch has to initialize `Wire` first; ES8311 driver skips `i2c_driver_install` if already running. Order matters.
- **Pin comments lie**: The board `.ino` comment said `DC=2, BL=21`. The actual `#defines` said `DC=46, BL=45`. Always trust the defines.

### First PR

The hardware bring-up was done in a branch. First (and so far only) PR of the project: `claude/esp-boot-firmware-setup-7lA8C`. Merged the same day.

---

## Day 3 — April 11: Voice, LED, Face Animations, Deployment

### What happened

Got the full voice pipeline working end-to-end on hardware. Tap and hold the screen → records via I2S mic → Opus-encodes on the ESP32 → streams over WebSocket → Google STT → Gemini Flash → ElevenLabs TTS → Opus → WebSocket back to ESP32 → plays through speaker.

Time to first audio: ~1.5 seconds. That number is the result of the streaming architecture — STT starts before recording ends, LLM starts streaming before STT finishes, TTS starts sentence by sentence before the full response is generated.

Deployed the backend to a VPS via Dokploy with Docker. Ran into a wall: Google Cloud credentials. The production container needs the service account JSON, but mounting volumes in Dokploy requires Docker Swarm mode. Solution: base64-encode the entire JSON and pass it as an environment variable. Ugly but it works.

### The personality problem

Early Aksa was... boring. Formal. Every response sounded like a customer service chatbot.

I rewrote the personality prompt. Then rewrote it again. Then again.

Current Aksa is gen-Z, sarcastic, uses casual Indonesian slang, makes jokes about Hendra's code, keeps responses short and punchy. The personality iteration continued across multiple days — it's not code, it's character design, and it takes as many tries to get right.

One specific discovery: **no text abbreviations in voice output**. I had "lol", "tbh", "omg" in the prompt. ElevenLabs TTS read them letter by letter — "el oh el". Removed all abbreviations; added the rule "speak these out, don't abbreviate for voice".

### Status LED (WS2812B)

Added LED status synced to bot state: green = idle, blue = listening, yellow = thinking, cyan = speaking, red = offline. Non-blocking animations (breathe, pulse, blink). Runs on FreeRTOS timer, no dedicated task.

### 11 idle micro-animations

Instead of a static face when nothing is happening, Aksa does random small movements every 8–20 seconds: look around, blink twice, peek curiously, yawn, disappear and reappear, roll her eyes, wink, bounce, doze off and snap awake, chew something, sigh. The face feels alive even when idle.

---

## Day 4 — April 12: The Hard Day (SSL, Audio, Provisioning)

This was the most technically dense day of the project.

### SSL on ESP32

Connecting to my backend over WSS (WebSocket Secure) required SSL support in the WebSocket library. The `ArduinoWebsockets` library had `setInsecure()` for ESP8266 but **not for ESP32**. The method existed in the class but called `setInsecure()` on the wrong underlying TCP client.

I had to patch the library source directly — `esp32_tcp.hpp` and `websockets_client.cpp`. Added `setInsecure()` to `SecuredEsp32TcpClient`, wired it up as the fallback when no CA cert is provided.

The patched files are in `firmware/patches/`. A PlatformIO pre-build script copies them over the library source before compilation. This means the patch survives `pio run -t clean` and library updates.

SSL also blew up memory. The TLS handshake needs ~40KB of contiguous heap. The ESP32-S3 has 8MB PSRAM but the heap for small allocations is internal SRAM. I reduced task stack sizes — display: 8K→6K, WebSocket: 12K→8K — and reduced the audio playback queue depth. Got free heap to ~138KB. Enough.

### Opus framing

The backend was encoding TTS audio with a **2-byte big-endian length prefix per frame**: `[len16][frame][len16][frame]...`

The firmware expected each WebSocket binary message to **be** one frame.

These are two completely different framing formats. The firmware was trying to decode the length bytes as Opus data and getting garbage audio. Fixed by adding `sendFramedOpusToDevice()` on the backend — parses the length-prefix format, sends each frame as a separate WebSocket message.

### BLE provisioning end-to-end

The setup flow for getting a device online: Flutter app advertises via BLE, user connects, app sends Wi-Fi credentials over GATT, device connects to Wi-Fi, app discovers device on local network via mDNS, registers it with the backend, sends the device token back via HTTP to the device's local server. All automatic, no manual steps.

Getting mDNS reliable was painful. ESP32's mDNS sometimes takes 10+ seconds to respond, sometimes doesn't respond at all until the first query fails. Added 4 retry attempts with increasing delays.

### Audio playback queue

Before: firmware decoded Opus frames synchronously in the WebSocket callback and tried to play them immediately.

After: WebSocket callback enqueues decoded PCM frames (non-blocking). A separate audio task on Core 0 dequeues with `portMAX_DELAY` and plays them. Added a 200ms jitter buffer — accumulate 10 frames before starting playback to smooth over network jitter.

---

## Day 5 — April 13: BLE Presence, Voice Preview, Multi-Language

### What happened

The BLE presence detection system: Flutter app advertises a UUID in the background, ESP32 scans RSSI continuously, a 3-state machine (PRESENT → LEAVING → AWAY) with hysteresis prevents flapping. When you sit at your desk, Aksa wakes up and greets you. When you walk away for long enough, she goes to sleep.

The challenge was that standard BLE advertising (using the app as a peripheral) broadcasts the UUID clearly. **Reverse scanning** turned out to be more reliable — the app advertises manufacturer-specific data instead of just a service UUID, and the ESP32 filters on the manufacturer ID. More noise rejection, more consistent RSSI readings.

Getting background BLE advertising working on iOS required specific `UIBackgroundModes` entries in `Info.plist` and careful handling of Core Bluetooth's restrictions. The app can advertise in the background but iOS throttles it. Acceptable for presence detection (you're at your desk for minutes, not milliseconds).

### Voice preview

Added a "Test Voice" button in the Flutter app's voice settings page. Taps the backend `/devices/:id/voice/preview` endpoint with a sample text, backend synthesizes TTS with current voice settings, streams the result to the device. The device plays it through the speaker immediately.

The first implementation synthesized a hardcoded string. Changed to a custom text input field — users can type any test phrase.

### Multi-language

Added language support for voice settings and bot responses. Indonesian and English. Backend detects the selected language from device settings and adjusts the system prompt accordingly. ElevenLabs voices have different quality for different languages — documented which presets work best for each.

---

## Day 6 — April 14: Face v2, Intercom, Battery, OTA, Images

This was the longest commit day: **56 commits**.

### Face animation v2 ("Nova" style)

The original face used circles and ellipses for eyes and mouth. It looked like a basic robot face. I redesigned it with **rounded rectangle eyes** (geometric, modern, more character) and bezier arc mouths (smooth curves instead of polylines).

The new eye system has:
- **Top-lid tilt** via `tiltInner`/`tiltOuter` fields — different tilt angles for inner and outer corners of the eyelid. Makes expressions like HAPPY (lifted outer corners) and ANGRY (inner corners dropped) feel natural.
- **Audio-reactive scaling** — eye width scales with audio amplitude. Loud → wider eyes. Quiet → slight squint. Blink suppression during loud speech.
- **Per-expression talking mouth shapes** — HAPPY has a smile-open mouth when talking. SAD has a frown-open. FOCUSED has a tight closed mouth. Each expression has its own character instead of the same generic talking animation.

Getting the eyelid tilt to work without visual artifacts took four fix commits: clamp the tilt angle, guard against `bodyH <= 0`, replace filled triangle wedges (which left corners) with scanline fills (which fill the exact shape needed).

### Voice intercom

Added a walkie-talkie style intercom feature. Flutter app can send a voice message directly to the device — record in app → stream to backend → forward to device WebSocket → plays through speaker. Device plays it with an "intercom" face expression. The reply flow: device records a response → streams back through backend → app receives audio → plays in app. Full two-way.

Added a temporary volume override — during an intercom session, the backend can push a volume level to the device (louder for intercom, back to normal after).

### Battery

The ES3C28P board has a battery ADC on GPIO9 connected to the LiPo voltage divider. Reading it is non-trivial:
1. The raw ADC reading has a significant pre-read false positive on first sample — need to discard the first reading.
2. The voltage-to-percentage curve is non-linear (LiPo curve, not linear mapping).
3. Need to detect USB power vs. battery — at 4.2V+ the device is USB-powered, show 100% and a "charging" indicator instead of a degraded battery reading.
4. The deprecated ADC constant `ADC_ATTEN_11db` was renamed in recent ESP-IDF. Had to find the new constant name.

Battery readings are polled every 30 seconds. Low battery triggers: a voice alert ("hey, I'm running low"), a red LED override, and automatic power saving (dim display earlier, sleep sooner).

Battery percentage flows all the way to the Flutter app via the `device:info` WebSocket event → backend persists it in the session → REST API includes it → app shows it in the device detail status bar.

### OTA firmware updates

Backend endpoint triggers an OTA update: device downloads firmware binary from a URL, verifies SHA-256, stages it. The actual `esp_ota_begin/write/end` flash sequence is stubbed — hardware testing needed before running that live. Status LED shows a slow pulse during download. Download can be cancelled via `ota:cancel` WebSocket event.

### Image display

Added the ability to push an image to the device display from the app. Backend downloads the image, resizes to fit within the device's PSRAM budget (~60KB), sends binary data over WebSocket, device renders it on screen. Useful for showing photos, weather maps, custom artwork.

PSRAM budget was tricky — the ESP32's PSRAM is large (8MB) but allocation failures are silent. Added a maximum byte cap on the backend side before sending, with explicit logging when the cap is hit.

---

## Day 7 — April 15 (Today): Sleep/Restart, Voice Transcription

### Sleep and restart

Added remote sleep and restart commands for devices. Backend endpoint → WebSocket event → device executes `esp_restart()` or enters deep sleep. The restart is useful after OTA updates; sleep is useful for power saving when leaving for an extended period.

### Voice input transcription pipeline

The transcription UI: app shows a waveform visualization while recording, sends audio to backend, gets back a text transcript. More useful than just showing the raw audio blob — you can verify what the bot heard.

---

## Recurring Challenges

### Memory constraints on ESP32

Everything on the ESP32 comes down to memory. The chip has 8MB PSRAM but it's slow external memory — internal SRAM is only ~512KB and critical operations (DMA buffers, FreeRTOS task stacks, TLS heap) need internal SRAM.

The `pcmBuffer` (raw audio) was initially allocated in PSRAM and caused audio glitches. Moved to internal SRAM. The PSRAM sprite buffer for the display has to be pre-allocated before Wi-Fi initialization — Wi-Fi grabs memory before PSRAM initialization is complete if you're not careful.

Every feature addition required checking free heap. The rule: if free heap drops below ~80KB, the next SSL handshake or large audio frame will crash.

### BLE on iOS

iOS treats BLE advertising very differently from Android. Background advertising is allowed but throttled. Core Bluetooth requires specific `UIBackgroundModes` in `Info.plist`. The app's BLE state monitoring needed explicit handling for when the user turns Bluetooth off — update UI, stop advertising, show a permissions dialog.

Getting the presence detection to work on both platforms required different advertising strategies and different RSSI calibration values (iOS and Android report RSSI differently for the same physical distance).

### Audio quality

The first end-to-end voice test produced audio that was audible but clearly degraded — choppy, slight pitch artifacts, occasional dropouts. Over four days, the audio quality improved through a series of targeted fixes:

1. Opus bitrate: was unset (defaulted to ~6kbps VOIP mode). Set to 64kbps AUDIO mode. Near-transparent quality for speech.
2. Jitter buffer: 200ms of audio accumulated before playback starts.
3. Frame pacing on backend: send 5 frames, pause 75ms. Prevents ESP32 TLS buffer overflow.
4. Static stereo buffer in `writeSpeaker()`: replaced per-frame malloc/free with a static buffer. Removed allocation jitter.
5. Volume scaling: 30dB range mapped to 0-100% slider. Previous linear mapping made quiet sounds inaudibly quiet.

### SSL + ArduinoWebsockets

Described in Day 4. The patch approach (copy patched files over library source via pre-build script) is robust but feels like a hack. The right fix is to submit a PR to the upstream library — adding proper `setInsecure()` support for ESP32 would benefit anyone using this library with an ESP32-S3 on WSS.

### Personality takes iteration

There's no algorithm for writing a bot personality. I rewrote Aksa's system prompt multiple times across multiple days. The current version is the result of noticing specific failure modes:
- Too formal → added explicit "no formal language" instructions
- Too long → added "keep responses under 2 sentences unless asked for detail"
- Text abbreviations read aloud → banned all abbreviations from voice output
- Wrong cultural references → added Indonesian cultural awareness
- No identity → explicitly defined her: desk companion, built by Hendra, no camera, push-to-talk only

---

## Numbers

| Metric | Value |
|--------|-------|
| Days of active development | 7 |
| Total commits | 216 |
| Backend: unit tests | 215 |
| Backend: E2E tests | 45 |
| Flutter app: pages | 24 |
| Flutter app: BLoC tests | 60 |
| Firmware: source modules | 25 |
| Firmware: lines of code | ~8,954 |
| Design docs | 16 |
| Busiest day (commits) | Day 6 — 56 commits |

---

## What's Next

The software is done. The hardware is working. What's left is physical:

1. **3D-printed enclosure** — Retro CRT TV shape. 2.8" portrait display becomes the screen. Speaker grille on the back. USB-C and buttons accessible from the top. PCB mounts 180° rotated so the ports line up.
2. **Battery** — 1.25mm 2P connector (not the more common JST PH 2.0 — found this out the hard way when the JST connector I ordered didn't fit). 1000-2000mAh LiPo.
3. **OTA flash** — Wire up `esp_ota_begin/write/end` once I can test the flash cycle safely on the real hardware.
4. **Face animation tuning** — Expression timing, mouth visibility, eye proportions — all of these need to be dialed in by looking at the actual hardware in real lighting, not just the simulator.

---

## Reflections

Building this in a week was possible because I had a very clear design upfront — 16 documentation files written before a single line of code. The architecture doc, the audio pipeline doc, the database schema, the firmware module list — all of it existed before the first commit. When I sat down to implement, I was filling in a spec, not discovering requirements.

The hardest parts weren't algorithm problems. They were:
- Hardware bring-up: finding the right library, the right settings, the right init order for a generic Chinese board with no English docs
- Memory management on a constrained device where every allocation decision matters
- Audio quality: lots of small fixes that each contributed a small improvement, no single silver bullet
- Personality writing: can't be unit tested

The most satisfying moment was the first full end-to-end voice round-trip on the physical hardware. Hold the screen, speak a sentence, hear Aksa's voice come back through the speaker 1.5 seconds later. That's the moment when a project goes from "code on a computer" to "a thing that exists in the world."
