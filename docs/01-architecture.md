# 01 — System Architecture

---

## Three actors

The system has three main actors:

1. **ESP32-S3 bot** (hardware) — captures audio, plays responses, shows a face
2. **NestJS backend** (brain) — orchestrates AI processing, stores data, serves APIs
3. **Flutter app** (remote control) — provisions devices, manages settings and history

---

## Data flow separation

Each connection between actors serves a specific purpose:

| Connection | Transport | Purpose |
|------------|-----------|---------|
| ESP32 <-> Backend | WebSocket | Real-time bidirectional Opus audio streaming |
| Flutter app <-> ESP32 | BLE | Local configuration and provisioning (no internet needed) |
| Flutter app <-> Backend | REST/HTTP | Conversation history, memory management, account data |
| Backend -> Gemini | HTTPS | Decoupled STT, LLM, and TTS API calls |

**Key principle:** The ESP32 never talks to Gemini directly. The backend is the single orchestration point for all AI processing. This keeps API keys secure and allows server-side memory injection before each LLM call.

---

## System diagram

```
Flutter App
  |-- BLE --> ESP32 (local config/control)
  '-- HTTP/WS --> NestJS Backend (history, memory, account -- JWT auth)

ESP32
  |-- BLE <-- Flutter App (config)
  |-- WebSocket --> NestJS Backend (Opus audio streaming -- device token auth)
  '-- MicroSD (local TTS cache, resilience audio, recording buffer, OTA staging)

NestJS Backend
  |-- WebSocket <-- ESP32 (audio/AI -- device token auth)
  |-- REST API <-- Flutter App (data -- JWT auth)
  |-- PostgreSQL (users, devices, conversations, memory -- source of truth)
  |-- Redis (TTS audio cache, session state, rate limits, usage counters)
  '-- Gemini / Google Cloud APIs (STT, LLM, TTS)
```

---

## Request lifecycle (voice interaction)

A single voice interaction flows through the system like this:

```
1. User taps ESP32 screen (touch-to-talk)
2. ESP32 captures mic audio via I2S
3. ESP32 encodes audio to Opus frames
4. ESP32 streams Opus frames to backend over WebSocket
5. User releases screen -> ESP32 sends audio:end event
6. Backend decodes Opus to PCM
7. Backend sends PCM to Google STT -> receives transcript
8. Backend prepends relevant memories + personality to prompt
9. Backend sends prompt + transcript to Gemini LLM -> receives response text
10. Backend sends response text to Google TTS -> receives audio
11. Backend encodes TTS audio to Opus
12. Backend streams Opus frames back to ESP32 over WebSocket
13. ESP32 decodes Opus and plays audio through speaker
14. Backend stores transcript + response in database
15. Backend extracts memories asynchronously (post-conversation)
```

---

## Component ownership

| Component | Responsible for | Does NOT do |
|-----------|----------------|-------------|
| ESP32 | Audio I/O, display, touch, BLE, WebSocket client | AI processing, API key storage, data persistence |
| Backend | Auth, AI orchestration, memory, data storage, REST API | Audio playback, display rendering, BLE |
| Flutter app | User auth, BLE provisioning, settings UI, history browsing | Audio processing, AI calls, direct device data storage |

---

## Backend architecture pattern

The backend follows a **Ports and Adapters** (hexagonal) pattern adapted to NestJS conventions. The goal is clean separation between business logic and external providers, so any provider (Gemini, Google STT, ElevenLabs, etc.) can be swapped by changing one file without touching the orchestration layer.

### How it works

```
                 Ports (interfaces)              Adapters (implementations)
                 ==================              =========================

Gateway/        ISttProvider                     GoogleSttProvider
Controllers  -> ILlmProvider      <- injected <- GeminiLlmProvider
     |          ITtsProvider                     GoogleTtsProvider
     v          IAudioCodec                      OpusAudioCodec
  AiService     IMemoryRepository                PostgresMemoryRepository
(orchestrator,
 depends only
 on ports)
```

- **Ports** are TypeScript interfaces that define what each capability must do (e.g., `ISttProvider.transcribe()`)
- **Adapters** are concrete classes that implement a port using a specific SDK (e.g., `GoogleSttProvider` uses `@google-cloud/speech`)
- **Orchestrators** (like `AiService`) depend only on ports via NestJS injection tokens — they never import a concrete provider
- **Swapping** a provider means writing a new adapter and changing one line in the module's `providers` array

This is not a premature abstraction — the AI provider space moves fast. STT, LLM, and TTS providers change pricing, quality, and availability regularly. The interface boundary exists because swapping is a near-certainty, not a hypothetical.

See [06-backend-api.md](06-backend-api.md) for the full interface definitions, implementations, and module wiring.

---

## Related docs

- [02-auth.md](02-auth.md) — How each connection is authenticated
- [04-audio-pipeline.md](04-audio-pipeline.md) — Detailed audio pipeline architecture
- [06-backend-api.md](06-backend-api.md) — Backend module structure with ports and adapters
- [08-ble-provisioning.md](08-ble-provisioning.md) — BLE connection details
