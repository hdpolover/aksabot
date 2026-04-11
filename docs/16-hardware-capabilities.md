# 16 — Hardware Capabilities & Opportunities

> Based on the ES3C28P board spec ([15-hardware-spec.md](15-hardware-spec.md)).
> Organized by current usage status — what's active, what's planned, and what's
> untapped potential for Aksabot.

---

## 1. Currently Leveraged

These hardware features have firmware modules written and are functionally
complete (pending real hardware testing).

### 1.1 I2S Audio (ES8311 Codec + FM8002E Amp + MEMS Mic)

**What it does:** Full-duplex audio — microphone captures voice, speaker plays
TTS responses. The ES8311 codec handles ADC/DAC conversion over I2S, and the
FM8002E Class-D amplifier drives the speaker.

**Current implementation:**
- Mic capture at 16kHz/16-bit mono → Opus encode → WebSocket stream to backend
- Backend TTS response → Opus decode → I2S playback through speaker
- VAD (Voice Activity Detection) with adaptive noise floor for auto end-of-speech
- Amplifier enable/disable via GPIO1 (LOW = on)
- Resilience audio preloaded into PSRAM for offline/error states

**Relevant modules:** `audio_io.cpp`, `opus_codec.cpp`, `es8311.cpp`, `vad.cpp`

### 1.2 ILI9341V Display (240x320 IPS TFT)

**What it does:** Renders the bot's animated face, clock, timers, and status
overlays via 4-line SPI.

**Current implementation:**
- 6 display modes: face, clock, pomodoro, reminder, countdown, status
- 12 face expressions with smooth transitions and per-expression mouth shapes
- 8 idle micro-animations (look around, double blink, curious, yawn,
  disappear/reappear, eye roll, wink, bounce) firing every 8-20s
- Per-eye independent scaling (wink, curious peek, yawn squint)
- Whole-face pop scale (disappear/reappear with overshoot)
- Listening nod (gentle vertical oscillation)
- Breathing-synced idle mouth, pursed thinking mouth, sad tremble
- Expression triggers: backend `face:expression` WS event, presence
  arrival (happy), presence departure (sad), errors (confused)
- Connection dot indicator (green/yellow/red, top-left corner)
- TFT rendering stubbed in `display_hw` namespace — swap for real SPI driver
  when hardware arrives

**Relevant modules:** `face.cpp`, `face.h`, `display.cpp`, `boot_screen.cpp`

### 1.3 FT6336G Capacitive Touch

**What it does:** Detects taps, holds, and long presses on the screen surface
via I2C interrupt.

**Current implementation:**
- Event abstraction: tap, hold_start, hold_end, long_press, wake
- Debounce and hold duration tracking
- Touch events drive BotState transitions and display mode changes
- Serial simulation for Phase 1 development (no hardware yet)

**Relevant modules:** `touch.cpp`

### 1.4 Wi-Fi (802.11 b/g/n)

**What it does:** Connects to backend over WebSocket for the full AI pipeline.

**Current implementation:**
- Auto-connect from NVS-stored credentials (fallback to compile-time constants)
- Reconnect with exponential backoff
- Connection status reflected on display (dot indicator) and BIOS status dashboard

**Relevant modules:** `wifi.cpp`, `ws_client.cpp`

### 1.5 NVS Flash

**What it does:** Persistent key-value storage for settings that survive reboot.

**Current implementation:**
- Stores Wi-Fi SSID/password, device token, volume, brightness, presence settings
- BLE provisioning writes credentials to NVS
- Falls back to compile-time defaults when NVS is empty

**Relevant modules:** `nvs_storage.cpp`

### 1.6 MicroSD Card (SDIO 4-bit)

**What it does:** Bulk storage for cached audio, logs, and OTA images.

**Current implementation:**
- Uses `SD_MMC` (SDIO 4-bit) driver with pins CLK=38, CMD=40, D0-D3=39/41/48/47
- Falls back to 1-bit SDIO mode if 4-bit fails
- TTS cache: SHA-256 keyed Opus files, LRU eviction at 100MB cap
- Recording buffer: captures audio during WebSocket disconnect, resends on
  reconnect
- Resilience audio: fallback clips loaded from `/audio/resilience/` at boot
- Debug logging: rolling 1MB log file with module tags and severity
- OTA staging: downloaded firmware stored before flashing

**Relevant modules:** `sd_storage.cpp`, `tts_cache.cpp`, `recording_buffer.cpp`,
`resilience_audio.cpp`, `debug_log.cpp`, `ota_update.cpp`

### 1.7 PSRAM (8MB OPI)

**What it does:** Large working memory for audio buffers and preloaded assets.

**Current implementation:**
- Opus encoder/decoder workspace
- Resilience audio clips preloaded at boot
- Audio ring buffers for capture and playback

### 1.8 RGB LED (WS2812B, GPIO42)

**What it does:** Single addressable RGB LED for at-a-glance status indication.

**Current implementation:**
- FastLED library with RMT peripheral on ESP32-S3
- Non-blocking animations: SOLID, BREATHE, PULSE, BLINK, FAST_BLINK, OFF
- Sine-based breathe curve with brightness floor (never fully dark)
- Max brightness capped at 40/255 (status indicator, not a flashlight)
- Auto-syncs to BotState via `syncToState()` (called from `syncFaceToState()`)
- Override modes for low battery, OTA, and focus mode

**Color/pattern mapping:**

| State | Color | Pattern |
|-------|-------|---------|
| Idle + connected | Green | Slow breathe |
| Idle + WiFi only (no WS) | Yellow | Slow breathe |
| Listening | Blue | Solid |
| Thinking | Amber | Pulse |
| Speaking | Cyan | Solid |
| Offline / no WiFi | Red | Slow blink |
| Focus mode | Purple | Dim solid |
| Low battery | Orange | Fast blink |
| Sleeping | Off | — |
| OTA in progress | White | Pulse |

**Relevant modules:** `status_led.cpp`, `status_led.h`, `main.cpp`

### 1.9 BOOT Button (GPIO0)

**What it does:** Hardware button, active LOW.

**Current implementation:** Used for BIOS menu entry during boot. Also serves as
ESP32-S3 download mode trigger (hold during power-on).

**Relevant modules:** `boot_screen.cpp`

---

## 2. Planned but Not Yet Built

These features have design docs and/or firmware stubs, but the implementation is
incomplete — mostly blocked on real hardware.

### 2.1 BLE GATT Provisioning Server — DONE

**What it provides:** First-time setup flow — Flutter app connects via BLE,
sends Wi-Fi credentials and device token, ESP32 stores them in NVS and connects
to backend.

**Implementation:**
- NimBLE GATT server with 4 services:
  - 0xFFE0 — WiFi provisioning (SSID write, password write, status notify)
  - 0xFFE1 — Device auth (token write, auth status notify)
  - 0xFFE2 — Device control (volume read/write, brightness read/write)
  - 0xFFE3 — Device status (battery read/notify, WiFi RSSI read, uptime read)
- Server callbacks for client connect/disconnect with auto-restart advertising
- WiFi SSID+password callbacks: store to NVS, trigger `wifi_manager::reconnect()`,
  spawn background task to monitor WiFi connect and notify status
- Device token callback: store to NVS, notify auth status
- Volume/brightness callbacks: store to NVS, apply immediately (brightness
  uses `fadeBrightness()`)
- Provisioning gate in `main.cpp`: blocks boot until BLE credentials arrive
  when device is unconfigured
- Flutter app: full 5-step BLE provisioning flow (scan → connect → Wi-Fi creds
  → register + write token → name → done)

**Relevant modules:** `ble_manager.cpp`, `ble_manager.h`, `main.cpp`,
`nvs_store.cpp`

### 2.2 BLE Presence Detection — DONE (Full Stack)

**What it provides:** Auto wake/sleep based on whether the user's phone is
nearby. Flutter app advertises a BLE UUID (0xFFE4), ESP32 scans RSSI to
determine proximity, backend generates welcome-back greetings with TTS audio.

**Flutter app (complete):**
- `BlePresenceService`: advertises 0xFFE4 UUID in low-power background mode
- Settings UI: enable/disable, RSSI threshold, grace period, silent wake
- Auto-restore advertising on app launch
- iOS/Android background BLE modes configured

**ESP32 firmware (complete):**
- `PresenceScanCallbacks`: scans for 0xFFE4, feeds RSSI to `presence_detector`
- `initScanOnly()`: lightweight BLE init for post-WiFi scanning
- 3-state machine (PRESENT → LEAVING → AWAY) with rolling average + grace period
- State changes: HAPPY face on arrival, SAD face on departure
- Sends `presence:arrived` / `presence:departed` to backend via WebSocket
- Auto wakes display on arrival, dims+sleeps on departure
- Adaptive scan intervals (5s present, 2.5s leaving, 30s away)

**Backend (complete):**
- `AudioGateway`: handles `presence:arrived` and `presence:departed` WS events
- `ProactiveService.onPresenceArrived()`: generates welcome-back greeting with
  LLM, contextual with away duration and user memories
- Skips greeting for brief absences (< 5 minutes)
- Long absences (> 30 min) get longer greeting; short ones get casual "hey!"
- First return of the day delegates to `checkGreeting()` for morning briefing
- Sends `face:expression` (happy/sad) to firmware alongside presence events
- Welcome-back text is TTS-synthesized and sent as audio frames

**Relevant modules:**
- Firmware: `ble_manager.cpp`, `presence_detector.cpp`, `main.cpp`
- Backend: `audio.gateway.ts`, `proactive.service.ts`, `types.ts`
- App: `ble_presence_service.dart`, `presence_settings_page.dart`

### 2.3 Battery Level Monitoring

**What it provides:** Read battery voltage from GPIO9 ADC to determine charge
level.

**What exists:** `BATTERY_ADC` pin defined in config.

**What's missing:** ADC reading code, voltage-to-percentage conversion, status
bar integration, low-battery alerts.

### 2.4 Display Backlight PWM Dimming — DONE

**What it provides:** Smooth brightness control with fade transitions instead of
instant on/off.

**Implementation:**
- LovyanGFX `Light_PWM` driver on GPIO45 at 12kHz (configured in `lgfx_config.h`)
- Non-blocking fade engine in `display::tick()` using smoothstep interpolation
  (`t*t*(3-2t)`) for ease-in-out curves
- `display::fadeBrightness(target, durationMs)` — public API, overrides any
  active fade mid-transition
- `userBrightness` tracked separately so wake always restores the correct level
- NVS brightness loaded on boot via `nvs_store::getBrightness()`
- BLE brightness write callback uses fade for smooth remote adjustment

**Fade timing:**

| Transition | Duration |
|-----------|----------|
| Wake (0 → active) | 300ms |
| Sleep (active → 0) | 200ms |
| Active → Dim | 500ms |
| Dim → Active | 250ms |
| BLE/config change | 200ms |

**Relevant modules:** `display.cpp`, `display.h`, `power_manager.cpp`,
`ble_manager.cpp`, `main.cpp`, `lgfx_config.h`

---

## 3. Untapped Capabilities

Hardware features that are available on the board but not yet part of any
Aksabot design doc or implementation plan. These represent expansion
opportunities.

### 3.1 Battery Intelligence

**Hardware:** GPIO9 ADC reads battery voltage. 3.7V LiPo, saturation at 4.24V.

**Opportunities:**

| Feature | Description | Effort |
|---------|-------------|--------|
| Battery percentage in BIOS dashboard | ADC read → voltage-to-% curve → BIOS status | Low |
| Push level to Flutter app | Send battery % over WebSocket → app dashboard | Low |
| Low-battery voice alert | Bot says "I'm running low, plug me in" | Low |
| Auto power saving | Dim display + reduce volume when below 20% | Medium |
| Deep sleep on critical | Enter deep sleep below 5% to prevent damage | Medium |
| Charge status detection | Detect USB power presence vs battery-only | Low |

**Why it matters:** Without battery monitoring, the bot dies without warning.
With it, the bot manages its own power gracefully — a basic requirement for a
battery-powered desk companion.

### 3.2 PWM Backlight Dimming — PARTIALLY DONE

**Hardware:** GPIO45 supports LEDC PWM output. The ILI9341V backlight is
4x white LEDs driven by a FET.

**Done:**
- Smooth fade on wake/sleep (smoothstep ease-in-out)
- Smooth fade on ACTIVE ↔ DIM power state transitions
- User-configurable brightness persisted to NVS, applied on boot
- BLE remote brightness adjustment with fade

**Remaining opportunities:**

| Feature | Description | Effort |
|---------|-------------|--------|
| Time-based auto brightness | Bright during work hours, dim in evening | Low |
| Breathing effect | Slow backlight pulse during "thinking" state | Low |
| Ambient light adaptation | Pair with a light sensor on spare GPIO (see 3.7) | Medium |

### 3.3 RGB LED as Status Indicator — DONE

Fully implemented — see Section 1.8 for details. FastLED library with
non-blocking animations, auto-synced to BotState, with override modes for
low battery, OTA, and focus mode.

### 3.4 UART Expansion (GPIO43/44)

**Hardware:** Hardware UART0 on a 1.25mm 4P header. Independent from USB.

**Opportunities:**

| Use Case | Description | Effort |
|----------|-------------|--------|
| External serial debug | Live logging without occupying USB (which powers the device) | Low |
| CO2 / air quality sensor | UART-based sensors (MH-Z19B, SenseAir S8) → feed readings to bot context | Medium |
| GPS module | Location awareness for weather/timezone (niche use case) | Medium |
| Secondary MCU | Offload LED animations or servo control to a smaller MCU | High |

**Why it matters for Aksabot:** The most practical use is connecting an air
quality sensor. The bot could say "CO2 is getting high, maybe open a window" —
fits the desk companion persona perfectly.

### 3.5 Spare GPIO Expansion (GPIO 2, 3, 14, 21)

**Hardware:** Four free GPIO pins on a 1.25mm 4P header. Can serve as digital
I/O, ADC, or SPI.

**Opportunities:**

| Peripheral | Pins Needed | What It Enables |
|------------|-------------|-----------------|
| PIR motion sensor | 1 (digital) | Presence detection without BLE — works for anyone near the desk, not just the paired phone user |
| Light sensor (LDR + resistor) | 1 (ADC) | Ambient light level → auto-adjust display brightness |
| Servo motor (SG90) | 1 (PWM) | Physical head nod/shake, tilt toward user — expressive robotics |
| Passive buzzer | 1 (PWM) | Quick notification beeps without spinning up the full audio pipeline |
| Physical button | 1 (digital) | Dedicated mute or focus-mode toggle |
| NeoPixel strip | 1 (data) | Ambient desk lighting that reacts to bot state |
| Two servos (pan + tilt) | 2 (PWM) | Full head movement — look at user, look away when sleeping |

**Priority picks for Aksabot:**
1. **Light sensor** (GPIO2 as ADC) — auto-brightness, minimal effort
2. **Servo** (GPIO3 as PWM) — physical expressiveness, high personality impact
3. **PIR sensor** (GPIO14 as digital) — backup presence detection

### 3.6 I2C Bus Expansion

**Hardware:** Shared I2C bus (GPIO16 SDA, GPIO15 SCL) exposed on 1.25mm 4P
header. Currently used by touch (0x38) and ES8311 codec. Can add more devices at
non-conflicting addresses.

**Compatible I2C peripherals:**

| Sensor | Address | What It Provides |
|--------|---------|-----------------|
| BME280 | 0x76 / 0x77 | Temperature, humidity, barometric pressure |
| APDS-9960 | 0x39 | Gesture detection, ambient light, proximity |
| BH1750 | 0x23 / 0x5C | Precise ambient light level (lux) |
| SHT30 | 0x44 / 0x45 | High-accuracy temperature + humidity |
| VL53L0X | 0x29 | Time-of-flight distance sensor (gesture/presence) |
| MPU6050 | 0x68 | Accelerometer + gyroscope (tap/shake detection on the device itself) |

**Best fits for Aksabot:**
1. **BME280** — "It's 28C and humid in here" adds environmental awareness to the
   companion persona
2. **APDS-9960** — gesture recognition (wave to dismiss reminders, swipe without
   touching the screen) + ambient light in one chip
3. **VL53L0X** — detect hand hovering over the device as a wake gesture

### 3.7 Deep Sleep with Wake Sources

**Hardware:** ESP32-S3 supports deep sleep with GPIO, timer, and touch pad wake.

**Available wake sources on this board:**

| Source | GPIO/Method | Use Case |
|--------|-------------|----------|
| Touch INT | GPIO17 (ext0 wake) | Tap screen to wake from deep sleep |
| BOOT button | GPIO0 (ext0 wake) | Press button to wake |
| Timer | RTC timer | Wake for scheduled reminders, then sleep again |
| BLE | Light sleep only | Maintain BLE presence scanning during sleep |

**Power profile:**

| State | Estimated Current | Battery Life (1000mAh) |
|-------|------------------|----------------------|
| Full active (display + audio) | ~560 mA | ~1.8 hours |
| Display only, idle | ~140 mA | ~7 hours |
| Light sleep (CPU paused) | ~5-10 mA | ~4-8 days |
| Deep sleep (RTC only) | ~10-50 uA | ~months |

**Why it matters:** With intelligent sleep management, the bot could run all day
on a LiPo battery at the desk, only waking for scheduled reminders or user
interaction. Paired with battery monitoring (3.1), this enables a truly portable
desk companion.

### 3.8 USB OTG (GPIO19/20)

**Hardware:** ESP32-S3 has native USB OTG support. GPIO19 (D-) and GPIO20 (D+)
are wired to the Type-C connector.

**Opportunities:**

| Mode | What It Enables | Effort |
|------|----------------|--------|
| USB CDC (current) | Serial debug + firmware flashing | Already works |
| USB Audio Device | Bot appears as a USB microphone/speaker on PC | High |
| USB HID Keyboard | Bot types out responses directly into your editor | High |
| USB Mass Storage | Access MicroSD contents from PC without card removal | Medium |

**Assessment:** These are technically possible but high-effort and niche. USB
Audio Device is the most interesting — it would let the bot act as a
conferencing microphone/speaker — but it's a significant firmware undertaking.
Low priority for Aksabot's core use case.

### 3.9 MicroSD as Content Platform

**Hardware:** MicroSD via SDIO with potentially large storage (32GB+).

**Beyond caching, the SD card could store:**

| Content | Description |
|---------|-------------|
| Custom face bitmaps | User-designed bot faces loaded from `/faces/` directory |
| Sound effects library | Notification chimes, ambient sounds, personality-specific audio |
| Local conversation backup | Privacy-conscious transcript storage, works offline |
| Configuration profiles | Multiple personality/reminder configs as JSON, switchable without backend |
| Font files | Custom display fonts for different languages or styles |
| Boot animations | Startup splash sequences loaded from SD |

**Why it matters:** The SD card transforms the bot from a cloud-dependent device
into something with local personality and content. Users could share face packs
or sound effect libraries.

---

## 4. Implementation Priority

Ranked by effort-to-impact ratio for Aksabot's desk companion use case.

### Tier 1 — Low effort, high impact (do first)

| # | Feature | Section | Effort | Status |
|---|---------|---------|--------|--------|
| 1 | Battery monitoring + BIOS dashboard | 3.1 | ~2 hours | |
| 2 | PWM backlight dimming + fade transitions | 3.2 | ~2 hours | DONE |
| 3 | RGB LED status mapping | 3.3 | ~3 hours | DONE |
| 4 | Low-battery voice alert | 3.1 | ~1 hour | |

### Tier 2 — Medium effort, high impact (do next)

| # | Feature | Section | Effort | Status |
|---|---------|---------|--------|--------|
| 5 | Deep sleep + touch/timer wake | 3.7 | ~4 hours | |
| 6 | Auto power saving (dim + volume on low battery) | 3.1 | ~3 hours | |
| 7 | Time-based auto brightness | 3.2 | ~2 hours | |
| 8 | Custom face bitmaps from SD | 3.9 | ~4 hours | |

### Tier 3 — Medium effort, medium impact (nice to have)

| # | Feature | Section | Effort |
|---|---------|---------|--------|
| 9 | Light sensor (LDR on spare GPIO) | 3.5 | ~2 hours + hardware |
| 10 | BME280 environment sensing | 3.6 | ~3 hours + hardware |
| 11 | Sound effects library on SD | 3.9 | ~3 hours |
| 12 | APDS-9960 gesture control | 3.6 | ~4 hours + hardware |

### Tier 4 — High effort or niche (future exploration)

| # | Feature | Section | Effort |
|---|---------|---------|--------|
| 13 | Servo motor for physical expression | 3.5 | ~6 hours + hardware |
| 14 | CO2 sensor via UART | 3.4 | ~4 hours + hardware |
| 15 | USB Audio Device mode | 3.8 | ~20 hours |
| 16 | USB HID keyboard output | 3.8 | ~15 hours |

---

## 5. Cross-References

- [15-hardware-spec.md](15-hardware-spec.md) — Pin mapping, electrical specs, physical dimensions
- [05-firmware.md](05-firmware.md) — Firmware module architecture
- [12-features.md](12-features.md) — Bot features and proactive behaviors
- [11-future-extensions.md](11-future-extensions.md) — Long-term expansion ideas (servos, camera, mobility)
- [04-audio-pipeline.md](04-audio-pipeline.md) — Streaming STT → LLM → TTS pipeline
- `firmware/include/config.h` — All GPIO pin definitions
