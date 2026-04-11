# Aksabot — AI Desk Companion

## What is this project?

A physical AI desk companion for a fullstack developer (Hendra). ESP32-S3 hardware with voice interaction, animated touchscreen face, persistent memory, and proactive behaviors (reminders, pomodoro, presence detection). Backend on NestJS, AI via Gemini, companion app in Flutter.

## Architecture decisions

- **Decoupled AI pipeline:** STT → LLM → TTS as separate stages, NOT Gemini multimodal live API. Each stage is swappable via ports and adapters (interfaces + NestJS injection tokens).
- **Streaming overlap:** STT runs during recording, LLM streams into sentence buffer, TTS per sentence. Time-to-first-audio ~1.5s instead of ~3s sequential.
- **Opus codec:** Audio encoded on ESP32 before sending. ~10x bandwidth reduction over raw PCM.
- **TypeORM** for database (not Prisma). Chosen for simplicity.
- **No LangChain.** Direct Gemini SDK calls wrapped in thin service adapters. Same swap-ability without the abstraction tax.
- **Redis** for TTS audio cache, WebSocket session state, and rate limiting. In-memory cache (NestJS cache-manager) for device config and memories.
- **MicroSD** on ESP32 for local TTS cache, resilience audio, recording buffer, OTA staging, debug logs.
- **Response pool** in PostgreSQL for recurring bot messages (reminders, greetings). LRU rotation, batch-generated via Gemini during idle, avoids API calls during daily operation.
- **BLE presence detection:** Flutter app advertises UUID in background, ESP32 scans RSSI to detect user at desk. Auto sleep/wake with personalized greeting.

## Tech stack

| Layer | Technology |
|-------|-----------|
| Firmware | ESP-IDF / Arduino + PlatformIO (ESP32-S3 N16R8) |
| Backend | NestJS + PostgreSQL + Redis |
| AI | Gemini API (decoupled STT → LLM → TTS) |
| Mobile | Flutter + flutter_blue_plus + flutter_ble_peripheral |
| Deploy | VPS + Dokploy |

## Documentation structure

All design docs are in `docs/`. This is the entry point:

| Doc | What it covers |
|-----|---------------|
| `00-overview.md` | Project overview, hardware, tech stack, timeline, doc index |
| `01-architecture.md` | System architecture, data flows, ports and adapters pattern |
| `02-auth.md` | JWT (app) + device tokens (ESP32) |
| `03-database.md` | Schema (6 tables), TypeORM entities, migrations |
| `04-audio-pipeline.md` | Streaming STT→LLM→TTS, sentence buffer, interruption, WebSocket protocol |
| `05-firmware.md` | I2S audio, display modes, BLE, MicroSD, power management, GPIO budget |
| `06-backend-api.md` | REST API, WebSocket gateway, interfaces, adapters, caching, module structure |
| `07-memory-service.md` | Memory extraction, decay, personality system |
| `08-ble-provisioning.md` | GATT services, provisioning flow, presence advertising |
| `09-flutter-app.md` | App screens, BLE integration, presence advertising |
| `10-risks-and-scope.md` | Risks, mitigations, deliberately excluded features |
| `11-future-extensions.md` | Expressive servos, desk mobility, camera, backend integrations |
| `12-features.md` | All bot capabilities — reactive, proactive, reminders, pomodoro, presence, response pool |
| `13-first-setup.md` | First-time setup — backend, firmware flash, app, pairing, troubleshooting |
| `14-remaining-features.md` | Remaining features buildable without hardware — roadmap and checklist |
| `15-hardware-spec.md` | ES3C28P board spec — GPIO pinout, display, touch, audio, SD, battery, dimensions |
| `16-hardware-capabilities.md` | Hardware capabilities inventory — what's used, planned, and untapped, with priority tiers |

## Database tables

1. `users` — accounts
2. `devices` — ESP32 registration, settings, personality
3. `conversations` — session tracking
4. `messages` — full transcript history
5. `memories` — extracted facts with confidence decay
6. `response_pool` — pre-generated bot responses (reminders, greetings) with LRU rotation

## Key patterns

- **Ports and adapters:** All external providers (STT, LLM, TTS, audio codec, TTS cache) are behind interfaces. Concrete implementations are swapped via NestJS module providers.
- **Response pool:** Recurring messages served from DB pool (LRU), not live Gemini calls. Pool refilled in background during idle.
- **Three-tier TTS cache:** Redis (backend) → MicroSD (ESP32 local) → API call (last resort).
- **Presence detection:** BLE RSSI scanning with 3-state machine (PRESENT → LEAVING → AWAY) and hysteresis to prevent flapping.
- **Sentence buffer:** Between LLM stream and TTS — detects sentence boundaries so TTS can start before the full response is generated.

## Current status

- **Backend: COMPLETE** (7 modules, 215 unit tests + 45 E2E tests, WS rate limiting, conversation search, forgot password)
- **Flutter app: Phase A+B+C+D COMPLETE** (24 pages, 5 BLoCs, 60 tests, BLE provisioning + presence, network banners, notifications, forgot password, zero analysis issues)
- **ESP32 firmware: 25 MODULES** (8,954 lines — audio, BLE, display, face, touch, NVS, presence, TTS cache, recording buffer, resilience audio, VAD, OTA, debug logging, power management, status LED, BIOS menu, boot screen, device server — TFT rendering stubbed, blocked on hardware)
- **ESP32 simulator:** `npm run esp:sim` keeps a device online for testing
- **All 16 design docs + app UI proposal updated** to reflect current state
- **API keys configured** (GEMINI_API_KEY, GOOGLE_APPLICATION_CREDENTIALS, ELEVENLABS_API_KEY)
- **Handoff:** `docs/handoffs/handoff-2026-04-11-2100.md` (latest session handoff)

### What's done — Backend
- NestJS backend with `core/` + `modules/` structure (7 modules)
- Docker-compose (PostgreSQL 16 on port 5489, Redis 7 on port 6312, NestJS on port 4280)
- All 6 TypeORM entities + migration applied
- Auth (JWT + device token + forgot/reset password), Devices CRUD + personality management
- AI pipeline: ports & adapters (5 interfaces, 5 adapters incl. Redis TTS cache), streaming orchestrator with cache hints
- WebSocket gateway: full audio lifecycle, STT streaming, interruption, session management, proactive events, presence events (arrived/departed with welcome-back TTS), face:expression push, per-device rate limiting (100 chunks/sec)
- Memory system: extraction via Gemini, confidence decay (daily cron), boost on access, CRUD
- Scheduler: per-device timers, response pool (LRU + batch generation), reminders, pomodoro state machine
- Proactive features: morning briefing, end-of-day wind-down, idle nudge, focus mode, presence-triggered welcome-back greeting (LLM + TTS, context-aware with away duration and memories)
- Rate limiting: Redis-backed (auth 5/min, API 60/min, WS audio 100/sec)
- Redis TTS cache with SHA-256 keying
- Conversation search: `?q=` full-text search via ILIKE join on messages
- 215 unit tests across 13 test files + 45 E2E tests (all controllers, services, gateway tested)
- WebSocket test script (`npm run ws:sim`) to simulate ESP32
- ESP32 simulator (`npm run esp:sim`) — creates device, connects via WebSocket, stays online
- `POST /devices/claim` — link existing device by token (for Wi-Fi manual flow)
- `GET /devices/:id/stats` — conversation/memory/pool counts

### What's done — Flutter App (Phase A+B+C+D)
- 24 pages, 60 BLoC tests, zero analysis issues, FVM 3.41.6
- 3-tab bottom nav (Home, Activity, Settings) via StatefulShellRoute
- Device dashboard (0/1/multi-device states), quick actions, recent conversations
- Activity tab: segmented conversations + memories with multi-device picker
- Settings tab: account card, theme, notifications toggle, sign out
- All core screens wired to backend: auth, devices, conversations, memories, reminders, pomodoro, focus mode, stats, response pool
- **5 BLoCs**: AuthBloc, DevicesBloc, ConversationsBloc, MemoriesBloc, SchedulerBloc (all registered in GetIt DI, all tested)
- **Add Device flow**: Wi-Fi (sends deviceToken to ESP32) + Bluetooth (5-step BLE provisioning with token write)
- **BLE provisioning**: scan → connect → Wi-Fi creds → register + write token via BLE → name → done
- **BLE presence detection**: `flutter_ble_peripheral` advertising 0xFFE4, settings UI with RSSI threshold/grace period, auto-restore on app startup
- **BLE service layer**: `core/ble/` with GATT constants + provisioning service + presence service
- **Network status banner**: `connectivity_plus` monitors connectivity, red banner slides in when offline
- **Local notifications**: `flutter_local_notifications` with 3 channels (reminders, pomodoro, device_alerts)
- **Forgot password**: two-step flow (email → 6-digit code + new password), wired to backend
- **Diagnostics page**: real API health checks, device stats from backend
- **Integrations page**: Weather toggle persisted to device settings
- **Voice & Audio page**: all settings persisted to device settings via PATCH API
- 6 planned UI screens for future features (display, OTA, motion, mobility — hardware-dependent)
- UI/UX proposal: `docs/app-ui-ux-proposal.md`
- Platform BLE permissions configured (iOS Info.plist + Android AndroidManifest.xml + UIBackgroundModes for BLE)

### What's done — Firmware
- **25 source modules** (25 .cpp, 30 .h, 8,954 lines): Wi-Fi, WebSocket, I2S audio, Opus codec, ES8311 codec, MicroSD (SDIO), NVS, BLE manager, presence detector, TTS cache, recording buffer, resilience audio, face animation, display manager, touch driver, VAD, OTA updates, debug logging, power management, status LED, BIOS menu, boot screen, device server, WiFi provisioning
- **NVS wrapper**: persistent Wi-Fi creds, device token, volume/brightness/presence settings — replaces hardcoded config.h values. Wi-Fi and WebSocket fall back to compile-time constants when NVS is empty.
- **BLE GATT provisioning server**: 4 services (WiFi 0xFFE0, Auth 0xFFE1, Control 0xFFE2, Status 0xFFE3). Flutter app writes credentials via BLE, ESP32 stores to NVS and connects.
- **BLE presence detection**: 3-state machine (PRESENT/LEAVING/AWAY) with RSSI rolling average, configurable grace period, hysteresis. `initScanOnly()` enables passive BLE scanning alongside WiFi. Sends `presence:arrived`/`presence:departed` events to backend. Happy face on arrival, sad face on departure. Auto sleep/wake display. Enabled from NVS on boot.
- **TTS cache manager**: SHA256-keyed Opus audio cache on SD, manifest.json persistence, LRU eviction (100MB cap). Audio accumulation during playback, cache-on-response:end with cacheKey parsing.
- **Recording buffer**: WebSocket disconnect resilience — audio capture loop auto-switches to SD buffering, resends on reconnect via `audio:start{buffered:true}` + binary frames.
- **Resilience audio**: loads fallback Opus clips from `/audio/resilience/` into PSRAM on startup (offline, error, stt_fail, boot, thinking, sleep, wake).
- **Face animation**: 12 expressions (idle, listening, thinking, speaking, confused, sleeping, offline, encouraging, calm, focused, happy, sad), blink timer (3-8s random), per-expression mouth shapes, breathing cycle, thinking dots, smooth transitions. 8 idle micro-animations (look around, double blink, curious peek, yawn, disappear/reappear, eye roll, wink, bounce) fire every 8-20s. Per-eye scaling (wink, curious). Whole-face pop scale (disappear). Listening nod. Backend `face:expression` WS event for LLM-driven sentiment. Automatic triggers: happy on presence arrival, sad on departure, confused on error.
- **Display manager**: 6 modes (face, clock, pomodoro, reminder, countdown, status), auto-return timer, connection dot indicator (green/yellow/red), transcript overlay. PWM backlight with smoothstep fade transitions (wake 300ms, sleep 200ms, dim 500ms). TFT rendering stubbed in `display_hw` namespace — swap for real ILI9341 when hardware arrives.
- **BIOS menu**: Status dashboard (WiFi signal, IP, backend online/offline, power source, SD card), audio test (beep/mic level/echo), WiFi scan, system info, setup WiFi, factory reset. Touch + BOOT button navigation.
- **Touch driver**: event abstraction (tap, hold_start, hold_end, long_press, wake), debounce, hold duration tracking, tap-to-wake from sleep. Serial simulation for Phase 1.
- **VAD (Voice Activity Detection)**: RMS energy + zero-crossing rate analysis, adaptive noise floor, configurable silence threshold (default 1.5s). Wired into audio capture loop — auto-stops recording on end-of-speech.
- **OTA updates**: HTTP download to SD, SHA-256 verification, staged flash (actual esp_ota_begin is a hardware TODO). Handles `ota:start` WebSocket event. Status LED shows OTA pulse.
- **Debug logging**: rolling log to `/logs/debug.log`, module tags, severity levels (D/I/W/E), 1MB rotation. LOG_I/LOG_W/LOG_E macros.
- **Status LED**: WS2812B RGB LED (GPIO42) via FastLED. Non-blocking animations (breathe, pulse, blink). Auto-syncs to BotState — green=idle, blue=listening, yellow=thinking, cyan=speaking, red=offline. Override modes for low battery, OTA, focus. Syncs on WS connectivity changes.
- **Power management**: ACTIVE → DIM → SLEEP state machine (30s dim, 5min sleep). Records interactions, auto-dims/sleeps, wakes on touch/presence/backend events. Backend proactive events (reminders, pomodoro, response:start, OTA) call recordInteraction() to wake display.
- FreeRTOS 3-task architecture: audio capture (Core 0), WebSocket polling (Core 1), display rendering at 30fps (Core 1)
- BotState changes auto-sync face expression + status LED; proactive events auto-switch display modes and wake display; audio amplitude feeds mouth animation

### What's next (all hardware-dependent)
1. Test firmware on real ESP32 hardware when it arrives
2. Implement TFT rendering in `display_hw` namespace (ST7789/ILI9341 SPI driver)
3. Implement capacitive touch IC reading in touch::feedRaw()
4. Wire esp_ota_begin/write/end in ota_update::apply()
5. FCM push notifications (backend + app integration)

## Backend structure

```
backend/src/
  core/
    config/       — env validation with class-validator
    database/     — 6 entities, migrations, data source
    cache/        — Redis client provider (global)
    common/       — ResponseInterceptor, GlobalExceptionFilter, CurrentUser decorator, RateLimitGuard
  modules/
    auth/         — JWT register/login/refresh/me + device token validation
    devices/      — CRUD + token gen + personality + settings + stats + claim, scoped to user
    ai/           — interfaces/ (5 ports), adapters/ (5 impls incl. TTS cache), orchestrator, sentence buffer
    gateway/      — WebSocket gateway, session manager, conversation persistence
    conversations/ — REST endpoints for history (paginated)
    memories/     — Extraction via Gemini, decay cron, confidence boost, CRUD
    scheduler/    — Response pool, reminders, pomodoro, proactive features, focus mode
```

## Conventions

- All docs use relative links to cross-reference each other
- Backend uses `core/` + `modules/` directory structure
- WebSocket events use `namespace:action` naming (e.g., `audio:chunk`, `proactive:reminder`, `presence:arrived`, `face:expression`)
- Database uses UUID primary keys, TIMESTAMPTZ for dates, JSONB for flexible config
- Raw `ws` adapter (not Socket.IO) — ESP32 speaks standard WebSocket
