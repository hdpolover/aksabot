# Aksabot Backend

NestJS backend for the Aksabot AI desk companion. Handles auth, device management, the AI pipeline (STT → LLM → TTS), WebSocket communication with ESP32 devices, memory system, and proactive scheduling.

## Quick Start

```bash
docker compose up -d          # PostgreSQL (port 5489) + Redis (port 6312)
cp .env.example .env          # Fill in API keys
npm run migration:run         # Apply database migrations
npm run start:dev             # Dev server on port 4280
```

## Commands

| Command | What it does |
|---------|-------------|
| `npm run start:dev` | Dev server with hot reload |
| `npm run build` | Production build to `dist/` |
| `npm test` | Run unit tests (Jest) |
| `npm run test:e2e` | Run E2E tests |
| `npm run test:cov` | Test coverage report |
| `npm run lint` | ESLint with auto-fix |
| `npm run ws:sim` | WebSocket simulator (test WS events) |
| `npm run esp:sim` | ESP32 simulator (creates device, stays online) |
| `npm run typeorm -- migration:generate src/core/database/migrations/MigrationName` | Generate migration |
| `npm run typeorm -- migration:run` | Run pending migrations |

## Project Structure

```
src/
  core/
    config/       — Env validation (class-validator)
    database/     — 6 TypeORM entities, migrations, data source
    cache/        — Redis client provider (global)
    common/       — ResponseInterceptor, GlobalExceptionFilter, CurrentUser decorator, RateLimitGuard
  modules/
    auth/         — JWT register/login/refresh/me + device token validation + forgot/reset password
    devices/      — CRUD + token gen + personality + settings + stats + claim, scoped to user
    ai/           — interfaces/ (5 ports), adapters/ (5 impls incl. Redis TTS cache), orchestrator, sentence buffer
    gateway/      — WebSocket gateway (raw ws), session manager, conversation persistence
    conversations/ — REST endpoints for history (paginated, searchable)
    memories/     — Extraction via Gemini, confidence decay (daily cron), boost on access, CRUD
    scheduler/    — Response pool, reminders, pomodoro, proactive features, focus mode
```

## Architecture Patterns

- **Ports and adapters**: All external providers (STT, LLM, TTS, audio codec, TTS cache) behind interfaces in `modules/ai/interfaces/`. Swap implementations via NestJS module providers and injection tokens.
- **No LangChain**: Direct Gemini SDK calls in thin adapter classes.
- **Raw WebSocket**: Uses `ws` adapter, not Socket.IO. ESP32 speaks standard WebSocket.
- **Response pool**: Pre-generated bot messages in PostgreSQL with LRU rotation. Avoids live Gemini calls for recurring messages (reminders, greetings).
- **Sentence buffer**: Between LLM stream and TTS — detects sentence boundaries so TTS starts before full response is generated.

## Database

6 TypeORM entities: `users`, `devices`, `conversations`, `messages`, `memories`, `response_pool`.

- UUID primary keys, TIMESTAMPTZ for dates, JSONB for flexible config
- Data source config: `src/core/database/data-source.ts`
- Migrations: `src/core/database/migrations/`

## WebSocket Protocol

Events use `namespace:action` naming. Key events:

| Event | Direction | Purpose |
|-------|-----------|---------|
| `audio:start` | ESP → Server | Begin recording session |
| `audio:chunk` | ESP → Server | Binary Opus audio frame |
| `audio:end` | ESP → Server | End recording, trigger STT → LLM → TTS |
| `audio:interrupt` | ESP → Server | User interrupted playback |
| `response:start` | Server → ESP | Audio response beginning |
| `response:text` | Server → ESP | LLM text (for transcript overlay) |
| `response:end` | Server → ESP | Audio response complete (with cacheKey) |
| `proactive:reminder` | Server → ESP | Health/wellness reminder |
| `proactive:pomodoro` | Server → ESP | Pomodoro state change |
| `presence:arrived` | ESP → Server | User's phone detected via BLE |
| `presence:departed` | ESP → Server | User's phone lost |
| `face:expression` | Server → ESP | Set face expression from LLM sentiment |
| `ota:start` | Server → ESP | Trigger firmware OTA update |

## Environment Variables

Required: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `JWT_SECRET`

Optional: `REDIS_HOST`, `REDIS_PORT`, `GEMINI_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`, `ELEVENLABS_API_KEY`, `JWT_EXPIRY`, `JWT_REFRESH_EXPIRY`

## Conventions

- One module per feature, each with its own service, controller (if REST), and spec files
- Guards for auth: `JwtAuthGuard` (REST), device token validation (WebSocket)
- Rate limiting: Redis-backed (auth 5/min, API 60/min, WS audio 100 chunks/sec)
- Tests: unit specs colocated with source in `*.spec.ts`, E2E in `test/`
- All REST responses wrapped by `ResponseInterceptor`
