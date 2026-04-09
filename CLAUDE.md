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

- **Backend: COMPLETE** (all phases implemented, 92 tests passing)
- **Phase 1 firmware: SCAFFOLDED** (Steps 8-11, all modules written, blocked on hardware)
- **All 13 design docs are complete**
- **API keys configured** (GEMINI_API_KEY + GOOGLE_APPLICATION_CREDENTIALS)

### What's done — Backend
- NestJS backend with `core/` + `modules/` structure (8 modules)
- Docker-compose (PostgreSQL 16 on port 5489, Redis 7 on port 6312, NestJS on port 4280)
- All 6 TypeORM entities + migration applied
- Auth (JWT + device token), Devices CRUD + personality management
- AI pipeline: ports & adapters (5 interfaces, 5 adapters incl. Redis TTS cache), streaming orchestrator with cache hints
- WebSocket gateway: full audio lifecycle, STT streaming, interruption, session management, proactive events
- Memory system: extraction via Gemini, confidence decay (daily cron), boost on access, CRUD
- Scheduler: per-device timers, response pool (LRU + batch generation), reminders, pomodoro state machine
- Proactive features: morning briefing, end-of-day wind-down, idle nudge, focus mode
- Rate limiting: Redis-backed (auth 5/min, API 60/min)
- Redis TTS cache with SHA-256 keying
- 92 unit tests across 10 test files
- WebSocket test script (`npm run ws:sim`) to simulate ESP32

### What's done — Firmware
- ESP32 firmware scaffolded: Wi-Fi, WebSocket client, I2S audio, Opus codec, MicroSD, main loop
- Serial-based touch simulation for testing without hardware

### What's next
1. Flash and test firmware on ESP32 when hardware arrives
2. Phase 2: Display + face animations (firmware, hardware-dependent)
3. Phase 4: Flutter companion app
4. Phase 5: Polish (VAD, OTA, power management)

## Backend structure

```
backend/src/
  core/
    config/       — env validation with class-validator
    database/     — 6 entities, migrations, data source
    cache/        — Redis client provider (global)
    common/       — ResponseInterceptor, GlobalExceptionFilter, CurrentUser decorator, RateLimitGuard
  modules/
    auth/         — JWT register/login/refresh + device token validation
    devices/      — CRUD + token gen + personality + settings, scoped to user
    ai/           — interfaces/ (5 ports), adapters/ (5 impls incl. TTS cache), orchestrator, sentence buffer
    gateway/      — WebSocket gateway, session manager, conversation persistence
    conversations/ — REST endpoints for history (paginated)
    memories/     — Extraction via Gemini, decay cron, confidence boost, CRUD
    scheduler/    — Response pool, reminders, pomodoro, proactive features, focus mode
```

## Conventions

- All docs use relative links to cross-reference each other
- Backend uses `core/` + `modules/` directory structure
- WebSocket events use `namespace:action` naming (e.g., `audio:chunk`, `proactive:reminder`, `presence:arrived`)
- Database uses UUID primary keys, TIMESTAMPTZ for dates, JSONB for flexible config
- Raw `ws` adapter (not Socket.IO) — ESP32 speaks standard WebSocket
