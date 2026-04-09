# 10 — Risks and Scope

---

## Risks and mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Audio latency too high | Bot feels sluggish, bad UX | Medium | Opus encoding reduces payload ~10x; stream STT results as they arrive; start TTS before full LLM response (streaming) |
| Gemini API costs | Monthly bill grows with usage | Medium | Cache TTS for repeated responses, rate limit per device (10 conv/min), usage tracking dashboard, billing alerts |
| ESP32 memory limits | Crashes during long audio streams | Medium | Chunked streaming (never buffer full audio), Opus frames are small (~60-120 bytes/20ms), monitor heap with `esp_get_free_heap_size()` |
| Wi-Fi reliability | Bot goes silent when connection drops | High | Auto-reconnect with exponential backoff, offline face indicator, no offline queueing (keeps complexity down) |
| STT/TTS provider lock-in | Can't switch if pricing or quality changes | Low | Decoupled pipeline -- each stage swappable independently (e.g., Whisper for STT, ElevenLabs for TTS) |
| Device token compromise | Unauthorized access to a user's bot | Low | Tokens are revocable from app; one token per device; validated on every WebSocket connection |
| I2S audio quality issues | Mic input too noisy or speaker output distorted | Medium | Test early in Phase 1; tune I2S config, consider AGC (automatic gain control); Opus handles some noise gracefully |
| Opus on ESP32 too CPU-heavy | Audio glitches or dropped frames | Low | ESP32-S3 dual-core can dedicate core 0 to audio; N16R8 variant has plenty of RAM; test with profiling early |

---

## Deliberately excluded (for now)

These features are intentionally out of scope for the initial prototype. Each has a clear reason for exclusion and can be revisited after the core product works.

### Wake word detection (ESP-SR)

**Why excluded:** Requires continuous audio processing, which conflicts with the power optimization goal (light sleep between interactions). You can't sleep and listen at the same time without a dedicated low-power audio chip.

**Revisit when:** The bot is used frequently enough that touch-to-talk feels like friction. At that point, consider adding a hardware VAD chip or accepting the power trade-off.

### MicroSD offline message queueing

**Why excluded:** The bot can't do anything useful without the backend and Gemini. Queueing voice messages for later processing adds significant complexity (MicroSD driver, queue management, replay logic) for a feature that provides almost no value -- by the time the message is processed, the context has changed.

**Instead:** Show an offline face expression and reconnect automatically. Simple and honest.

### Multi-user per device

**Why excluded:** Would require voice identification (speaker diarization) to know who's talking, which adds AI complexity and latency. V1 assumes one user per device -- a personal desk companion.

**Revisit when:** There's a clear use case (e.g., family device, shared office bot). At that point, consider voice enrollment and per-user memory separation.

### Gemini multimodal live API (single call)

**Why excluded:** The decoupled STT -> LLM -> TTS pipeline is more debuggable, observable, and swappable. A single multimodal call is a black box -- you can't see the transcript, can't cache TTS, can't swap one stage without replacing the whole thing.

**Revisit when:** Latency is measurably a problem and Gemini's multimodal API offers a significant speed advantage. Can be added as an optional fast path alongside the decoupled pipeline.

---

## Phase 5: Polish items (weeks 12-14)

These are the finishing touches that turn the prototype into a daily-use product:

| Item | Priority | Notes |
|------|----------|-------|
| 3D-printed enclosure | High | Speaker grille, mic hole, display window, USB-C access |
| Audio VAD | High | Auto-detect end of speech (replace manual release in touch-to-talk) |
| Power management | Medium | Display dimming, light sleep, wake on touch |
| Auto-reconnect | High | Exponential backoff for Wi-Fi and WebSocket |
| OTA firmware updates | Medium | Backend triggers update, ESP32 downloads and flashes |
| Error handling | High | Graceful degradation across all failure modes |
| TTS response caching | Low | Cache Opus audio for repeated phrases (greetings, errors) |
| Usage tracking | Medium | Per-device conversation count, API cost estimation |

---

## Post-V1 roadmap

Once V1 is stable and in daily use, see [11-future-extensions.md](11-future-extensions.md) for planned extensions:

1. **Expressive servo movement** — head tilt/nod, highest impact upgrade
2. **Backend integrations** — weather, calendar, timers via tool provider pattern
3. **Desk mobility** — wheels, cliff sensors, navigation (ambitious)
4. **Camera/vision** — requires hardware addition, long-term

---

## Related docs

- [00-overview.md](00-overview.md) — Timeline and phase overview
- [04-audio-pipeline.md](04-audio-pipeline.md) — Latency budget details
- [05-firmware.md](05-firmware.md) — Power management strategy
- [11-future-extensions.md](11-future-extensions.md) — Full post-V1 extension specs
