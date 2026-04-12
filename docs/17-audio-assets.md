# 17 — Audio Assets

Sound effects and UI audio clips that bring Aksa to life beyond TTS responses. All clips are generated via ElevenLabs Sound Effects, stored on the SD card, and played back from PSRAM or directly from SD on demand.

---

## Overview

Aksa uses two categories of audio assets:

| Category | Path | Loaded into | Purpose |
|----------|------|-------------|---------|
| Resilience clips | `/audio/resilience/` | PSRAM on boot | Fallback audio for offline/error states |
| UI clips | `/audio/ui/` | SD stream on demand | Interaction feedback, state changes, notifications |

The resilience clips are already wired into the `resilience_audio` module. The UI clips will need a lightweight `ui_audio` module (future work) — they don't need PSRAM preloading since they're played on demand.

---

## Technical constraints

- **Max file size**: 64 KB per clip (the resilience loader rejects larger files)
- **Target duration**: <2 seconds for most clips, <4 seconds for boot/complete fanfares
- **Format**: Opus, 16kHz mono (the ESP32 Opus decoder expects this)
- **Conversion command** (after downloading from ElevenLabs):

```bash
ffmpeg -i input.mp3 -c:a libopus -b:a 16k -ac 1 -ar 16000 output.opus
```

---

## SD card layout

```
/audio/
  resilience/
    boot.opus
    wake.opus
    sleep.opus
    thinking.opus
    offline.opus
    error.opus
    stt_fail.opus
  ui/
    tap.opus
    hold_start.opus
    recording_stop.opus
    wifi_connected.opus
    server_connected.opus
    server_disconnected.opus
    notification.opus
    pomodoro_start.opus
    pomodoro_break.opus
    pomodoro_complete.opus
    presence_arrived.opus
    presence_departed.opus
```

---

## Resilience clips — `/audio/resilience/`

These seven clips are loaded into PSRAM at boot and played when the backend is unreachable or an error occurs. They must be the shortest and most robust audio in the system.

### Sonic direction
Warm, slightly digital, never harsh. Think: a small robot that has feelings. The clips should feel like natural extensions of Aksa's personality — self-aware, a little dramatic about its own problems.

---

### `boot.opus` — Startup chime

**Trigger**: Device power-on, after Wi-Fi connects.

**ElevenLabs prompt**:
> A warm, soft 3-note ascending digital chime — low, mid, then high — gentle reverb tail, about 1.2 seconds. Friendly and inviting, like a small robot waking up for the first time each morning. Clean attack on each note, not percussive.

---

### `wake.opus` — Waking from sleep

**Trigger**: Display wakes from sleep state (touch, presence arrival, or proactive event).

**ElevenLabs prompt**:
> A bright, quick rising two-tone digital pip — crisp and energetic, about 0.4 seconds. Like eyes snapping open. Clean attack, short decay, no reverb tail.

---

### `sleep.opus` — Going to sleep

**Trigger**: Device enters sleep state (display off, low power).

**ElevenLabs prompt**:
> A soft, descending two-tone electronic tone — gently fading to near silence, about 0.5 seconds. Peaceful and warm, like settling down. Slightly rounded edges, not harsh. The second note is noticeably quieter than the first.

---

### `thinking.opus` — Processing / ambient loop

**Trigger**: While Aksa is processing audio (STT → LLM pipeline). Played on loop.

**ElevenLabs prompt**:
> A subtle, rhythmic triple soft beep — three quiet digital pulses evenly spaced, each about 0.25 seconds with a 0.3 second gap between them. Like a gentle processor hum. Barely noticeable, ambient, not intrusive. Designed to loop cleanly.

---

### `offline.opus` — Backend unreachable

**Trigger**: WebSocket fails to connect or drops and can't reconnect.

**ElevenLabs prompt**:
> A soft, low descending two-tone drone — slightly muffled, like a signal cutting out. About 0.6 seconds. Subdued, not alarming. The second tone is lower and quieter than the first, ending in near-silence. Conveys "I lost connection" without causing panic.

---

### `error.opus` — General error

**Trigger**: Something went wrong that isn't specifically handled.

**ElevenLabs prompt**:
> A short, gentle double buzz — soft and rounded, not harsh or jarring, about 0.35 seconds. Two low pulses close together. Signals something went wrong without startling anyone. Think: soft rubber bump, not electric shock.

---

### `stt_fail.opus` — Didn't catch that

**Trigger**: STT returns empty or unintelligible transcription.

**ElevenLabs prompt**:
> A single soft descending pip with a slightly questioning character — about 0.2 seconds. Like a small shrug in audio form. Gentle and non-alarming. One short tone that bends slightly downward, then fades.

---

## UI clips — `/audio/ui/`

These clips provide feedback for touch interactions, connectivity changes, and scheduled events. They're played from SD on demand.

### Sonic direction
Slightly more playful than the resilience clips. Still warm and digital — not overly cute or childish. Each clip should feel like it belongs to the same character: Aksa, who has gen-z energy and a sense of humor. Short, crisp, and never annoying on repeat.

---

### `tap.opus` — Touch tap feedback

**Trigger**: Every screen tap.

**ElevenLabs prompt**:
> A crisp, satisfying single-tap UI click — very short, about 0.08 seconds. Clean digital tap, not mechanical, not harsh. Like a modern phone keyboard tap but warmer. Slightly rounded edges.

---

### `hold_start.opus` — Recording begins

**Trigger**: User holds the screen to start talking.

**ElevenLabs prompt**:
> A soft, gently rising tone that fades in over 0.3 seconds — warm, slightly electronic. Like a microphone activating. Inviting and open-sounding. Signals "I'm listening now" without being loud.

---

### `recording_stop.opus` — Recording sent

**Trigger**: User releases the screen and audio is sent to the backend.

**ElevenLabs prompt**:
> Two quick soft descending pips in rapid succession — about 0.2 seconds total. Clean and satisfying. Like a message being sent off. First pip slightly higher, second slightly lower.

---

### `wifi_connected.opus` — Wi-Fi established

**Trigger**: Wi-Fi connection succeeds during boot or reconnect.

**ElevenLabs prompt**:
> Two warm ascending tones — clear and pleasant, about 0.45 seconds. Like finding a signal. Reassuring, not overly celebratory. The second tone is a clean step up from the first.

---

### `server_connected.opus` — Backend WebSocket connected

**Trigger**: WebSocket handshake with the NestJS backend succeeds.

**ElevenLabs prompt**:
> A warm 3-note ascending chime — digital but with slight warmth, about 0.6 seconds. Like a handshake completing. Feels like "we're online and ready." Clean and bright, not too loud.

---

### `server_disconnected.opus` — WebSocket dropped

**Trigger**: WebSocket connection drops unexpectedly.

**ElevenLabs prompt**:
> Two quiet, slightly subdued descending tones — about 0.4 seconds. Gentle concern without alarm. Like a connection quietly fading. The second tone is softer and slightly lower than the first.

---

### `notification.opus` — General reminder ping

**Trigger**: Health reminders (stand up, hydration, eye break, posture), generic proactive events.

**ElevenLabs prompt**:
> A clear, friendly 2-note chime — bell-like, the first note slightly lower, the second higher with a soft decay tail. About 0.6 seconds. Attention-getting but not intrusive. Like a gentle tap on the shoulder.

---

### `pomodoro_start.opus` — Focus session begins

**Trigger**: User starts a 25-minute pomodoro work block.

**ElevenLabs prompt**:
> A focused, clean single ascending tone with a subtle reverb tail — grounding and steady, about 0.5 seconds. Signals "head down, let's go." Not energetic — calm and purposeful. Like taking a breath before starting.

---

### `pomodoro_break.opus` — Break time

**Trigger**: 25-minute work block ends, 5-minute break begins.

**ElevenLabs prompt**:
> A playful 2-tone bounce — bright and slightly bouncy, about 0.5 seconds. Conveys relief and lightness. The second tone is higher and has a tiny, upward spring quality. Unmistakably different from `pomodoro_start`.

---

### `pomodoro_complete.opus` — Full pomodoro cycle done

**Trigger**: 4 pomodoro cycles complete (long break begins), or user explicitly finishes their session.

**ElevenLabs prompt**:
> A small triumphant 3-note ascending chime with a gentle reverb tail — warm, celebratory but not overblown, about 1 second. Like a quiet victory fanfare. You worked hard. Aksa is proud of you (lowkey).

---

### `presence_arrived.opus` — User detected at desk

**Trigger**: BLE RSSI scan confirms user's phone is nearby — state transitions to PRESENT.

**ElevenLabs prompt**:
> A warm, inviting 2-note welcome chime — bright and happy, about 0.5 seconds. Like "oh, you're here!" Light and genuinely glad-sounding. The second note is a bright step up with a short, warm decay.

---

### `presence_departed.opus` — User left desk

**Trigger**: BLE RSSI scan confirms user is away — state transitions to AWAY.

**ElevenLabs prompt**:
> A gentle 2-note descending tone — quiet, soft, calm. About 0.4 seconds. Like a small wave goodbye. Not sad, just acknowledging. The second note fades to near-silence.

---

## Generation tips

1. **Tool**: Use ElevenLabs Sound Effects (not TTS) — the audio generation tool that takes descriptive prompts.
2. **Too long**: Add "very short, under X seconds" and regenerate.
3. **Too harsh**: Add "warm, soft edges, no sharp transients."
4. **Too quiet**: Use the volume slider in ElevenLabs before downloading.
5. **Doesn't loop cleanly** (for `thinking.opus`): Add "designed to loop seamlessly, clean start and end."
6. **Regenerate freely** — sound effects generation is fast and cheap. Try 3–5 variations per clip and pick the best.
7. **Batch convert** after downloading:

```bash
for f in *.mp3; do
  ffmpeg -i "$f" -c:a libopus -b:a 16k -ac 1 -ar 16000 "${f%.mp3}.opus"
done
```
