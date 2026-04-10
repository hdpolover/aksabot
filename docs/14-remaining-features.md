# 14 — Remaining Features (No Hardware Required)

---

## Overview

This document tracked all features buildable without physical ESP32 hardware. **All items are now complete.**

---

## Backend — ALL COMPLETE

| # | Feature | Status | Details |
|---|---------|--------|---------|
| 1 | Missing test coverage | **DONE** | 13 test files: scheduler, proactive, reminder services + conversation persistence + all 4 controllers. 215 unit tests total. |
| 2 | E2E test suite | **DONE** | 45 tests in `test/app.e2e-spec.ts`: auth flow, devices CRUD, conversations, memories, access control. |
| 3 | WebSocket rate limiting | **DONE** | Per-device Redis counter on `ws:rate:<deviceId>`, 100 chunks/sec, 1s TTL. Fails open on Redis error. |
| 4 | Conversation search | **DONE** | `?q=` parameter on GET conversations, ILIKE join on messages table. |
| 5 | Forgot password | **DONE** | POST /auth/forgot-password (6-digit code, 15min expiry) + POST /auth/reset-password. |

## Flutter App — ALL COMPLETE

| # | Feature | Status | Details |
|---|---------|--------|---------|
| 6 | BLoC tests | **DONE** | 60 tests across 5 files (auth, devices, conversations, memories, scheduler). |
| 7 | Diagnostics page | **DONE** | Real API health checks, device stats from backend. |
| 8 | Integrations page | **DONE** | Weather toggle persisted to device settings via PATCH API. |
| 9 | Voice & Audio page | **DONE** | All 7 settings (preset, speed, stability, sounds, VAD) persisted to device settings. |
| 10 | Forgot password | **DONE** | Two-step page (email → code + new password), route added, login page linked. |

## Firmware — ALL COMPLETE

| # | Feature | Status | Details |
|---|---------|--------|---------|
| 11 | VAD module | **DONE** | `vad.cpp/.h` — RMS + ZCR analysis, adaptive noise floor, 1.5s silence threshold, wired into audio capture loop. |
| 12 | OTA verification | **DONE** | `ota_update.cpp/.h` — HTTP download to SD, SHA-256 verify, handles `ota:start` event. Flash is hardware TODO. |
| 13 | Debug logging | **DONE** | `debug_log.cpp/.h` — rolling `/logs/debug.log`, module tags, D/I/W/E levels, 1MB rotation, LOG_I/W/E macros. |
| 14 | Power management | **DONE** | `power_manager.cpp/.h` — ACTIVE→DIM→SLEEP, configurable timeouts, interaction recording, auto wake. |

---

## What remains (hardware-dependent only)

1. TFT display rendering (`display_hw` namespace stubs → real ST7789/ILI9341 SPI driver)
2. Capacitive touch IC reading (`touch::feedRaw()` → real SPI reads)
3. BLE GATT server for provisioning (write Wi-Fi creds + token to NVS via BLE)
4. BLE scanner wiring (`presence_detector::feedRssi()` ← real BLE scan results)
5. OTA flash operation (`ota_update::apply()` → `esp_ota_begin/write/end`)
6. FCM push notifications (backend token storage + push delivery)

---

## Related docs

- [05-firmware.md](05-firmware.md) — Firmware implementation status
- [06-backend-api.md](06-backend-api.md) — REST API endpoints
- [09-flutter-app.md](09-flutter-app.md) — App screens and state management
- [12-features.md](12-features.md) — Full feature list with phases
