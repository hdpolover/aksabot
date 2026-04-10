# 00 — Project Overview

**AI Desk Bot: ESP32-S3 + NestJS + Gemini + Flutter**
*April 2026*

---

## What is this?

A physical AI desk companion powered by ESP32-S3 with voice interaction, a touchscreen face, and persistent memory. The bot connects to a NestJS backend for AI processing via Gemini, and is managed through a Flutter companion app.

---

## Hardware

| Component | Details | Est. cost |
|-----------|---------|-----------|
| Hosyond ESP32-S3 2.8" | N16R8, 2.8" IPS touch, mic, speaker, Wi-Fi, BLE, MicroSD, USB-C, battery charging | Rp 435,600 |
| LiPo battery (optional) | 3.7V, 1000-2000mAh, JST PH 2.0 connector | Rp 15,000-30,000 |
| 3D-printed enclosure | Custom housing for desk placement | Rp 50,000-100,000 |

---

## Tech stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Firmware | ESP-IDF / Arduino + PlatformIO | Audio capture/encode, playback, display, BLE, WebSocket client, MicroSD cache |
| Backend | NestJS + PostgreSQL + Redis | WebSocket gateway, REST API, auth, memory service, AI orchestration, caching |
| AI | Gemini API (decoupled STT -> LLM -> TTS pipeline) | Speech-to-text, language model reasoning, text-to-speech -- as separate stages |
| Mobile app | Flutter + flutter_blue_plus | BLE provisioning, device config, history viewer, memory editor |
| Deployment | VPS + Dokploy | Backend hosting with CI/CD |

---

## Timeline summary

| Phase | Duration | Key milestone | Status | Details |
|-------|----------|---------------|--------|---------|
| 1. Audio pipeline + auth | Weeks 1-3 | End-to-end voice conversation with auth | **COMPLETE** | [04-audio-pipeline.md](04-audio-pipeline.md), [02-auth.md](02-auth.md) |
| 2. Display + interaction | Weeks 4-5 | Animated face with touch-to-talk and transcript | **SCAFFOLDED** (logic done, TFT rendering stubbed, blocked on hardware) | [05-firmware.md](05-firmware.md) |
| 3. Memory + personality | Weeks 6-8 | Bot remembers across sessions | **COMPLETE** | [07-memory-service.md](07-memory-service.md) |
| 4. Flutter app | Weeks 9-11 | Mobile setup, provisioning, and management | **COMPLETE** (Phase A+B+C+D: 23 pages, 5 BLoCs, BLE, network, notifications) | [09-flutter-app.md](09-flutter-app.md) |
| 5. Polish + reliability | Weeks 12-14 | Finished desk product | In progress (firmware resilience modules done, VAD/OTA pending) | [10-risks-and-scope.md](10-risks-and-scope.md) |

Total estimated timeline: **14 weeks** for a fully functional prototype. Phases can overlap -- backend memory work (Phase 3) can start while display work (Phase 2) is in progress.

**Current status (April 2026):** Backend fully implemented (7 modules, 215 unit tests + 45 E2E tests, WS rate limiting, conversation search, forgot password). Flutter app complete (24 pages, 5 BLoCs, 60 tests, BLE, network banners, notifications, forgot password). ESP32 firmware at 18 modules (4,049 lines) — all software-only features implemented including VAD, OTA verification, debug logging, power management. Only hardware-dependent items remain: TFT rendering, touch IC, BLE GATT server, BLE scanner.

---

## Document index

| Document | Description |
|----------|-------------|
| [00-overview.md](00-overview.md) | This file -- project overview, hardware, tech stack, timeline |
| [01-architecture.md](01-architecture.md) | System architecture, data flows, component diagrams |
| [02-auth.md](02-auth.md) | Authentication model -- JWT for app, device tokens for ESP32 |
| [03-database.md](03-database.md) | Database schema, table relationships, migrations |
| [04-audio-pipeline.md](04-audio-pipeline.md) | Decoupled STT -> LLM -> TTS pipeline, Opus codec, WebSocket protocol |
| [05-firmware.md](05-firmware.md) | ESP32 firmware -- I2S audio, display, touch, BLE, power management |
| [06-backend-api.md](06-backend-api.md) | NestJS REST API and WebSocket gateway specification |
| [07-memory-service.md](07-memory-service.md) | Memory extraction, decay algorithm, personality system |
| [08-ble-provisioning.md](08-ble-provisioning.md) | BLE GATT services and device provisioning flow |
| [09-flutter-app.md](09-flutter-app.md) | Flutter companion app -- screens, features, BLE integration |
| [10-risks-and-scope.md](10-risks-and-scope.md) | Risks, mitigations, and deliberately excluded features |
| [11-future-extensions.md](11-future-extensions.md) | Post-V1 extensions — expressive servos, desk mobility, integrations, camera |
| [12-features.md](12-features.md) | Bot capabilities — reactive features, proactive reminders, pomodoro, display modes |
