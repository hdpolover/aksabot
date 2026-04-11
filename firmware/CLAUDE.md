# Aksabot Firmware

ESP32-S3 firmware for the Aksabot AI desk companion. Handles audio I/O, display rendering, touch input, BLE provisioning/presence, WebSocket communication, and power management. Does NOT perform any AI processing — all intelligence lives on the backend.

## Quick Start

```bash
pio run                    # Build firmware
pio run -t upload          # Flash to device (USB-C)
pio device monitor         # Serial monitor (115200 baud)
```

## Board: ES3C28P

- **MCU**: ESP32-S3 N16R8 (16MB Flash, 8MB PSRAM, dual-core 240MHz)
- **Display**: ILI9341V 240x320 IPS TFT (4-line SPI)
- **Touch**: FT6336G capacitive (I2C, addr 0x38)
- **Audio**: ES8311 codec + FM8002E amp (I2S) + MEMS mic
- **SD Card**: SDIO 4-bit (use `SD_MMC`, not SPI `SD`)
- **LED**: WS2812B RGB on GPIO42
- **Battery**: 3.7V LiPo, ADC on GPIO9
- **BLE**: NimBLE stack (GATT server + passive scanner)

Pin mapping: `include/config.h`. Full board spec: `docs/15-hardware-spec.md`.

## Project Structure

```
firmware/
  include/          — Header files (.h) for all modules
    config.h        — GPIO pins, timing constants, Opus config
    credentials.h   — WiFi SSID/password, backend URL, device token (git-ignored)
    lgfx_config.h   — LovyanGFX display + touch + backlight config
    state.h         — BotState and PresenceState enums, global AppState
  src/              — Implementation files (.cpp)
    main.cpp        — Setup, loop, WS event handlers, touch handler, FreeRTOS tasks
  platformio.ini    — Board config, build flags, library dependencies
  partitions.csv    — Custom 16MB partition table (app0 4MB + app1 4MB for OTA)
```

## Module Architecture

All modules use **C++ namespaces** (not classes). Each `.cpp`/`.h` pair is a self-contained module with `init()`, `tick()`, and domain-specific functions.

| Module | Namespace | Purpose |
|--------|-----------|---------|
| `audio_io` | `audio_io` | I2S mic capture + speaker playback via ES8311 codec |
| `opus_codec` | `opus_codec` | Opus encode/decode for WebSocket audio |
| `es8311` | — | ES8311 codec I2C driver (ESP-IDF style) |
| `ws_client` | `ws_client` | WebSocket client with auto-reconnect |
| `wifi_manager` | `wifi_manager` | WiFi STA with exponential backoff reconnect |
| `display` | `display` | 6 display modes, backlight PWM fade, connection dot |
| `face` | `face` | 12 expressions, idle micro-animations, mouth shapes |
| `touch` | `touch` | Debounced touch events, tap-to-wake, serial simulation |
| `ble_manager` | `ble_manager` | GATT server (provisioning) + BLE scanner (presence) |
| `presence_detector` | `presence_detector` | 3-state machine (PRESENT/LEAVING/AWAY) |
| `nvs_store` | `nvs_store` | Persistent key-value settings (WiFi, token, volume, etc.) |
| `sd_storage` | `sd_storage` | MicroSD init + directory creation (SDIO 4-bit) |
| `tts_cache` | `tts_cache` | SHA-256 keyed Opus cache on SD, LRU eviction |
| `recording_buffer` | `recording_buffer` | Audio buffering during WS disconnect |
| `resilience_audio` | `resilience_audio` | PSRAM-loaded fallback audio clips |
| `vad` | `vad` | Voice Activity Detection (RMS + zero-crossing) |
| `power_manager` | `power_manager` | ACTIVE → DIM → SLEEP state machine |
| `status_led` | `status_led` | WS2812B RGB animations synced to BotState |
| `ota_update` | `ota_update` | OTA download + SHA-256 verify + staged flash |
| `debug_log` | `debug_log` | Rolling file log on SD with severity levels |
| `boot_screen` | `boot_screen` | Splash, POST checks, provisioning UI |
| `bios_menu` | `bios_menu` | Status dashboard + audio test + WiFi scan + system info |
| `device_server` | `device_server` | HTTP server for Flutter app token delivery |
| `wifi_provision` | `wifi_provision` | WiFi AP provisioning (legacy) |

## FreeRTOS Tasks

| Task | Stack | Priority | Core | Purpose |
|------|-------|----------|------|---------|
| `audioCaptureLoop` | 24KB | 5 | 0 | Mic read → Opus encode → WS send |
| `wsLoop` | 12KB | 3 | 1 | WebSocket poll + JSON event dispatch |
| `displayLoop` | 8KB | 3 | 1 | Face animation + display render @ 30fps |

Main `loop()` runs on Core 1: touch polling, power management tick, LED tick, connectivity sync.

## Conventions

- **Credentials**: `include/credentials.h` is git-ignored. Copy `credentials.h.example` and fill in values. NVS overrides compile-time defaults when set via BLE provisioning.
- **State machine**: `state.h` defines `BotState` (IDLE/LISTENING/THINKING/SPEAKING/OFFLINE/SLEEPING) and `PresenceState`. Global `appState` is accessed from multiple tasks (fields are `volatile`).
- **WebSocket events**: `namespace:action` format (e.g., `audio:start`, `face:expression`). JSON events handled in `onWsJson()`, binary Opus frames in `onWsBinary()`.
- **Display**: TFT rendering is stubbed in `display_hw` namespace inside `display.cpp`. Swap the rendering functions for real SPI driver calls when hardware arrives.
- **Serial simulation**: Touch events can be simulated via serial (`s`=hold start, `e`=release, `i`=tap, `w`=wake).
- **Memory**: Use PSRAM (`ps_malloc`) for large buffers. Regular heap for small allocations.

## Libraries

| Library | Version | Purpose |
|---------|---------|---------|
| LovyanGFX | ^1.2.0 | Display driver + touch + backlight PWM |
| ArduinoWebsockets | ^0.5.4 | WebSocket client |
| ArduinoJson | ^7.3.0 | JSON parse/serialize |
| arduino-libopus | git | Opus codec for ESP32 |
| NimBLE-Arduino | ^2.1.2 | BLE GATT server + scanner |
| FastLED | ^3.9.0 | WS2812B RGB LED via RMT |
