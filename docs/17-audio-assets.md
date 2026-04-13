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
    presence_arrived.opus
    presence_departed.opus
  emotion/
    confused.opus
    shrug.opus
    surprised.opus
    shocked.opus
    angry.opus
    disturbed.opus
    happy.opus
    sad.opus
    encouraging.opus
    calm.opus
    focused.opus
  sfx/
    rimshot.opus
    crickets.opus
    sad_trombone.opus
    drumroll.opus
    level_up.opus
    evil_laugh.opus
    chef_kiss.opus
    applause.opus
    hbd.opus
    roast.opus
    thinking_hard.opus
    mind_blown.opus
    sigh.opus
    gasp.opus
    deploy_success.opus
    build_fail.opus
    midnight.opus
    morning.opus
    coffee_time.opus
    rain.opus
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
> A warm, soft 3-note ascending electronic synth chime — three pure sine tones stepping up a major third each, low to high, about 1.2 seconds total. Gentle reverb tail on the final note only. Friendly and inviting, like a small robot waking up happy. Smooth onset on each note — no click or hard transient. No background noise.

---

### `wake.opus` — Waking from sleep

**Trigger**: Display wakes from sleep state (touch, presence arrival, or proactive event).

**ElevenLabs prompt**:
> A bright, quick rising two-tone electronic pip — ascending a perfect fifth, high register, crisp and energetic, about 0.4 seconds total. Like eyes snapping open. Sharp onset, very short decay, completely dry with no reverb tail. No background noise.

---

### `sleep.opus` — Going to sleep

**Trigger**: Device enters sleep state (display off, low power).

**ElevenLabs prompt**:
> A soft, descending two-tone electronic synth tone — stepping down a major third, about 0.5 seconds. The second note is noticeably quieter than the first and fades to near silence. Warm and rounded timbre, no sharp edges or hard attack. Peaceful, like slowly closing your eyes. Dry, no reverb. No background noise.

---

### `thinking.opus` — Processing / ambient loop

**Trigger**: While Aksa is processing audio (STT → LLM pipeline). Played on loop.

**ElevenLabs prompt**:
> Three quiet, evenly spaced soft electronic beeps — each pulse about 0.2 seconds with a 0.3 second gap between them, total about 1.5 seconds. Low-mid frequency, muted and ambient. Like a small processor quietly working. Barely noticeable, never intrusive. The clip starts and ends in silence so it loops seamlessly with no click or pop. No reverb tail. No background noise.

---

### `offline.opus` — Backend unreachable

**Trigger**: WebSocket fails to connect or drops and can't reconnect.

**ElevenLabs prompt**:
> A soft, low descending two-tone electronic sound — slightly muffled and slightly detuned, like a signal fading out. About 0.6 seconds. The second tone is lower in pitch and quieter than the first, ending in near-silence. Subdued and calm, not alarming — conveys "I lost the connection" without causing panic. Dry, no reverb. No background noise.

---

### `error.opus` — General error

**Trigger**: Something went wrong that isn't specifically handled.

**ElevenLabs prompt**:
> A short, gentle double electronic buzz — two soft low-frequency pulses very close together, about 0.35 seconds total. Rounded, muffled timbre — not harsh, not jarring, no sharp transients. Signals something went wrong without startling anyone. Think: the sound of a padded bump, not an electric shock. Completely dry, no reverb. No background noise.

---

### `stt_fail.opus` — Didn't catch that

**Trigger**: STT returns empty or unintelligible transcription.

**ElevenLabs prompt**:
> A single soft electronic pip that bends slightly downward in pitch, like a question mark — about 0.2 seconds. Gentle and non-alarming. Mid-range frequency, warm timbre. Fades to silence immediately after. Completely dry, no reverb tail. No background noise. Like a small audio shrug.

---

## UI clips — `/audio/ui/`

These clips provide feedback for touch interactions, connectivity changes, and scheduled events. They're played from SD on demand.

### Sonic direction
Slightly more playful than the resilience clips. Still warm and digital — not overly cute or childish. Each clip should feel like it belongs to the same character: Aksa, who has gen-z energy and a sense of humor. Short, crisp, and never annoying on repeat.

---

### `tap.opus` — Touch tap feedback

**Trigger**: Every screen tap.

**ElevenLabs prompt**:
> A single, extremely brief UI tap sound — electronic, not mechanical, warm and soft. Very short click with immediate silence — no reverb, no tail. Like a modern touchscreen keyboard tap but with rounded, non-harsh edges. Dry and clean. No background noise.

---

### `hold_start.opus` — Recording begins

**Trigger**: User holds the screen to start talking.

**ElevenLabs prompt**:
> A single soft electronic tone that fades in from silence and gently rises in pitch over about 0.35 seconds — warm synth timbre, slightly breathy. Like a microphone quietly switching on. Open and inviting, signals "I'm listening now" without being startling. Ends with a gentle natural decay. No harsh transients. No background noise.

---

### `recording_stop.opus` — Recording sent

**Trigger**: User releases the screen and audio is sent to the backend.

**ElevenLabs prompt**:
> Two quick electronic pips in rapid succession, descending — the first slightly higher, the second slightly lower, about 0.2 seconds total. Clean and satisfying, like a message being dispatched. Short decay on each pip, completely dry with no reverb. No background noise.

---

### `wifi_connected.opus` — Wi-Fi established

**Trigger**: Wi-Fi connection succeeds during boot or reconnect.

**ElevenLabs prompt**:
> Two warm ascending electronic synth tones — rising a perfect fourth, mid-range register, about 0.45 seconds. Reassuring and clean, like finding a signal. Not overly celebratory — just quietly confident. Short natural decay on the second tone. No background noise.

---

### `server_connected.opus` — Backend WebSocket connected

**Trigger**: WebSocket handshake with the NestJS backend succeeds.

**ElevenLabs prompt**:
> A bright 3-note ascending electronic chime — each note steps up a minor third, higher register than `wifi_connected`, with a gentle reverb tail on the last note, about 0.7 seconds total. Like a handshake completing and a door opening. Brighter and slightly more celebratory than `wifi_connected` — this is the moment everything is truly ready. No background noise.

---

### `server_disconnected.opus` — WebSocket dropped

**Trigger**: WebSocket connection drops unexpectedly.

**ElevenLabs prompt**:
> Two quiet, descending electronic tones — slightly muffled timbre, about 0.4 seconds. Mirrors `server_connected` in structure but reversed in mood — downward, fading, like a connection quietly disappearing. The second tone is softer and noticeably lower than the first. Gentle concern, not alarm. Dry, no reverb. No background noise.

---

### `notification.opus` — General reminder ping

**Trigger**: Health reminders (stand up, hydration, eye break, posture), generic proactive events.

**ElevenLabs prompt**:
> A clear, friendly 2-note bell chime — the first note lower, the second higher with a soft natural reverb decay tail. Bell-like overtones, warm rather than harsh. About 0.6 seconds. Attention-getting without being intrusive — like a gentle tap on the shoulder. No background noise.

---

### `presence_arrived.opus` — User detected at desk

**Trigger**: BLE RSSI scan confirms user's phone is nearby — state transitions to PRESENT.

**ElevenLabs prompt**:
> A warm, bright 2-note ascending electronic chime — the second note steps up a major sixth, giving it a slightly surprised and happy lift, about 0.5 seconds. Like "oh, you're back!" Distinctly warmer and more personal-feeling than `wifi_connected` — this one has a bit of genuine happiness in it. Short warm decay. No background noise.

---

### `presence_departed.opus` — User left desk

**Trigger**: BLE RSSI scan confirms user is away — state transitions to AWAY.

**ElevenLabs prompt**:
> A gentle 2-note descending electronic tone — stepping down a major sixth, mirroring `presence_arrived` but in reverse, about 0.4 seconds. The second note fades to near-silence. Soft and warm, not sad — just a small acknowledgment, like a quiet wave goodbye. Rounded timbre, no sharp edges. Dry, no reverb. No background noise.

---

## Emotion clips — `/audio/emotion/`

These play when the backend pushes a `face:expression` WS event — i.e., the LLM tagged a sentence with an emotion and Aksa is about to say it. They fire once at the start of that emotional moment, right before TTS begins.

### Sonic direction
Short, punchy, and characterful. Each clip should feel like the sound effect version of Aksa's personality — not a realistic human sound, but a stylised electronic/robotic expression. Keep them under 0.5 seconds. They should land fast, not linger.

---

### `confused.opus`

**Trigger**: `face:expression` → `confused` — Aksa didn't quite follow.

**ElevenLabs prompt**:
> A short, upward-bending electronic pip with a slight wobble at the top — like a question mark in sound form, about 0.3 seconds. Mid-range frequency, slightly uncertain character. Bends up then trails off with a tiny descending tail, as if unsure which way to go. Warm, not harsh. Dry, no reverb. No background noise.

---

### `shrug.opus`

**Trigger**: `face:expression` → `shrug` — Aksa doesn't know or doesn't care (classic gen-z energy).

**ElevenLabs prompt**:
> A lazy, slightly deflating two-tone electronic sound — the first tone is mid-range, the second is slightly lower and loses energy, about 0.35 seconds. Like a small balloon slowly releasing air. Rounded and soft, not sharp. Conveys "ehh, whatever." No reverb. No background noise.

---

### `surprised.opus`

**Trigger**: `face:expression` → `surprised` — something unexpected.

**ElevenLabs prompt**:
> A quick bright ascending electronic pip — sharp attack, fast rise in pitch, about 0.2 seconds. Like a small "oh!" in sound form. Crisp and energetic but not harsh. Completely dry, immediate cutoff after the peak. No reverb. No background noise.

---

### `shocked.opus`

**Trigger**: `face:expression` → `shocked` — frozen disbelief, more extreme than surprised.

**ElevenLabs prompt**:
> A very short sharp electronic jolt — a quick bright ping followed immediately by a low thud, total about 0.3 seconds. Like a record scratch cut short. The ping is high and crisp, the thud is low and soft. Creates a "wait, WHAT" character. No reverb. No background noise.

---

### `angry.opus`

**Trigger**: `face:expression` → `angry` — irritated, frustrated.

**ElevenLabs prompt**:
> A short, low, buzzy electronic growl — rough and slightly distorted texture, about 0.3 seconds. Like a small robot gritting its teeth. Low-mid frequency, rounded attack but with a slightly rough edge. Not alarming, but clearly expressing frustration. Cuts off cleanly. No background noise.

---

### `disturbed.opus`

**Trigger**: `face:expression` → `disturbed` — creeped out, unsettled.

**ElevenLabs prompt**:
> A short unsettled electronic warble — a mid-range tone that wobbles or modulates unevenly, about 0.35 seconds. Like a signal that's slightly corrupted or off-key in a creepy way. Not loud, not harsh — just subtly wrong. Fades out with a small glitch. No background noise.

---

### `happy.opus`

**Trigger**: `face:expression` → `happy` — genuinely pleased.

**ElevenLabs prompt**:
> A tiny bright two-note ascending electronic chime — very short, about 0.25 seconds. Light and cheerful, like a mini celebration. Higher-register than `presence_arrived` and much shorter — this is a quick internal "yay", not a greeting. Clean decay. No reverb. No background noise.

---

### `sad.opus`

**Trigger**: `face:expression` → `sad` — sympathetic, down.

**ElevenLabs prompt**:
> A single soft descending electronic tone — starts mid-range, falls to low, about 0.35 seconds. Slightly hollow timbre, like a small sigh. Fades gently to silence. Warm but melancholic. Not dramatic — just quietly sad. No reverb. No background noise.

---

### `encouraging.opus`

**Trigger**: `face:expression` → `encouraging` — cheerful, uplifting, motivating.

**ElevenLabs prompt**:
> A bright, upbeat short two-note electronic chirp — both tones ascending, the second with a small upward bounce, about 0.3 seconds. Energetic and positive, like a tiny cheer. Distinct from `happy.opus` — this one has more forward momentum, like "you've got this." Clean, dry. No background noise.

---

### `calm.opus`

**Trigger**: `face:expression` → `calm` — relaxed, gentle, soothing.

**ElevenLabs prompt**:
> A single slow, smooth electronic tone — fades in gently, sustains briefly at mid-range, then fades out, about 0.5 seconds. Very soft and rounded, like a quiet exhale. No sharp edges anywhere. Creates a sense of stillness. Slightly warm timbre. No background noise.

---

### `focused.opus`

**Trigger**: `face:expression` → `focused` — determined, locked in.

**ElevenLabs prompt**:
> A single low, clean electronic pulse — short and grounding, about 0.25 seconds. Low-mid frequency, firm attack but not harsh, clean cutoff. Like a small confirmation beep that says "I'm on it." Purposeful and steady. No reverb, completely dry. No background noise.

---

1. **Tool**: Use ElevenLabs Sound Effects (not TTS) — the audio generation tool that takes descriptive prompts.
2. **Too long**: Add "under X seconds total" and regenerate.
3. **Too harsh**: Add "soft rounded edges, no sharp transients, warm timbre."
4. **Too quiet**: Use the volume slider in ElevenLabs before downloading.
5. **Has background noise**: Add "completely silent background, pure tones only."
6. **Doesn't loop cleanly** (`thinking.opus`): Add "starts and ends in complete silence, loops without any click or pop."
7. **Clips sound too similar**: Run two back-to-back and listen for character differences. The prompts call out interval names (major third, perfect fifth, major sixth) — if the model ignores them, re-describe in plain terms ("a big upward jump" vs "a small step up").
8. **Regenerate freely** — sound effects generation is fast and cheap. Try 3–5 variations per clip and pick the best.
9. **Batch convert** after downloading:

```bash
for f in *.mp3; do
  ffmpeg -i "$f" -c:a libopus -b:a 16k -ac 1 -ar 16000 "${f%.mp3}.opus"
done
```
