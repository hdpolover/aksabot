# Face Recognition — Agent Handoff

## What This Is

Complete face recognition feature for aksabot. ESP32-CAM sends 1fps JPEG frames to NestJS backend via WebSocket. Backend runs buffalo_l ONNX (detect + embed), matches against enrolled face profiles in pgvector. Identified person is injected into the LLM conversation context on the main aksabot device.

## Repo

`/Users/mit06/Desktop/personal-projects/aksabot`
Branch: `main`

## Three Implementation Plans

All plans are written and committed. Execute them in order (backend → firmware-cam → Flutter):

1. `docs/superpowers/plans/2026-04-23-face-recognition-backend.md` — 7 tasks
2. `docs/superpowers/plans/2026-04-23-face-recognition-firmware-cam.md` — 5 tasks
3. `docs/superpowers/plans/2026-04-23-face-recognition-flutter.md` — 4 tasks

## Design Spec

`docs/superpowers/specs/2026-04-23-face-recognition-design.md`

## How to Execute

Use `superpowers:subagent-driven-development` skill. Fresh subagent per task + spec compliance review + code quality review after each task.

## Key Architectural Decisions (already decided, do not revisit)

- **buffalo_l ONNX in Node.js** via `onnxruntime-node` + `sharp`. No Python sidecar.
- **Embeddings stored as `float8[]`** PostgreSQL array. pgvector cosine search via `embedding::vector <=> $1::float8[]::vector` raw query.
- **Database uses `synchronize: true`** (not migrations). Add FaceProfile entity → TypeORM auto-creates table.
- **pgvector extension** must be enabled manually: `CREATE EXTENSION IF NOT EXISTS vector;` in PostgreSQL before starting backend.
- **Gateway uses raw WebSocket** (not Socket.IO). Messages parsed in `handleMessage()` in `audio.gateway.ts`. Binary frames sent as base64 JSON for vision frames.
- **pairedDeviceId** stored in camera device's `settingsJson.pairedDeviceId` — backend uses this to route `face:identity` events to the right aksabot session.
- **Always-on vs conversation-only** vision mode: ESP32-CAM sends frames only when `vision:start` received (default), or always if `config:update {vision_mode: "always"}`.
- **Match threshold: 0.4** cosine distance. Below = known person, above = unknown.

## Project Architecture (for context)

**Backend:** NestJS 11, TypeORM (`synchronize: true`), PostgreSQL 16 (port 5489), Redis 7 (port 6312). Modules: auth, devices, ai, gateway, conversations, memories, scheduler, firmware. Start: `npm run start:dev` in `backend/`.

**Gateway pattern:** `audio.gateway.ts` (86KB) handles all WS events. Uses raw WebSocket `ws` adapter (not Socket.IO). `handleMessage(client, deviceId, raw, isBinary)` dispatches by `msg.event`. Injects services: AiService, MemoriesService, SchedulerService, etc. `SessionManager` tracks per-device state (in-memory Map). Outbound events via `sendToDevice(deviceId, event, data)` using `deviceToSocket` Map.

**firmware-cam:** PlatformIO + Arduino, ESP32-CAM (AI-Thinker, OV3660). Existing: camera.cpp, motion.cpp, metrics.cpp, stream_server.cpp, main.cpp. FreeRTOS: captureLoop (priority 5, Core 1), mjpegTask (priority 4, Core 1), serverLoop (priority 3, Core 1). frameQueue (1-slot, drop-on-full) feeds frames from capture to MJPEG.

**Flutter:** FVM 3.41.6. BLoC pattern with GetIt DI. Existing BLoCs: AuthBloc, DevicesBloc, ConversationsBloc, MemoriesBloc, SchedulerBloc. Pages in `app/lib/features/devices/presentation/pages/`.

## Current State

- Plans: ✅ written and committed
- Implementation: ❌ not started
- ONNX models: ❌ need manual download from InsightFace buffalo_l model zoo
- pgvector: ❌ need manual `CREATE EXTENSION IF NOT EXISTS vector;` in PostgreSQL

## Manual Steps Required (cannot be automated)

1. Download `det_10g.onnx` (~16MB) and `w600k_r50.onnx` (~166MB) from InsightFace model zoo → place in `backend/models/buffalo_l/`
2. Run `CREATE EXTENSION IF NOT EXISTS vector;` in PostgreSQL (connect to aksabot DB)
3. After backend Task 1 (device creation): update `firmware-cam/include/credentials.h` with real DEVICE_TOKEN and BACKEND_HOST
4. After all devices claimed: `PATCH /devices/<camera-id>` with `settingsJson: {pairedDeviceId: "<aksabot-main-device-id>"}`

## Task Tracking

Tasks #13-27 in the task list. Backend: #13-19, firmware-cam: #20-23, Flutter: #24-27. All pending.

## Test Commands

```bash
# Backend tests
cd backend && npm test

# firmware-cam build
cd firmware-cam && pio run

# Flutter tests
cd app && flutter test && flutter analyze
```
