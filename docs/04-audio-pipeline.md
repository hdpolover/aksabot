# 04 — Audio Pipeline

---

## Design philosophy

The AI processing is split into **three independent stages** rather than a single multimodal API call. This is a deliberate architectural choice:

- **Swap-ability:** Each stage can use a different provider (e.g., Whisper for STT, ElevenLabs for TTS)
- **Observability:** You can log and debug each stage independently -- see the transcript, the prompt, and the response separately
- **Cacheability:** Common TTS responses can be cached (e.g., greetings, error messages)
- **Resilience:** One provider going down doesn't take out the entire pipeline

Critically, the three stages are **not sequential** -- they pipeline into each other. STT runs while the user is still speaking, LLM output streams into TTS sentence-by-sentence, and TTS audio streams to the ESP32 as it's generated. This overlap is what makes the latency acceptable.

If Gemini later offers a multimodal live API with acceptable latency, it can be added as an optional fast path.

---

## Pipeline overview

### Sequential (naive -- what we avoid)

```
[user speaks] -> [wait] -> [full STT] -> [wait] -> [full LLM] -> [wait] -> [full TTS] -> [play]
                                                                                           ~3-4s gap
```

### Streaming overlap (what we do)

```
[user speaks]──────────┐
  [STT streams partial]─┤
                        ├─[final transcript ready ~200ms after user stops]
                        ├─[LLM starts immediately, streams tokens]
                        │   ├─[sentence 1 complete]─→[TTS 1]─→[Opus]─→[ESP32 plays]
                        │   ├─[sentence 2 complete]─→[TTS 2]─→[Opus]─→[ESP32 plays]
                        │   └─[sentence 3 complete]─→[TTS 3]─→[Opus]─→[ESP32 plays]
                        └─[done]
```

Time-to-first-audio is dramatically lower because:
1. STT is already done (or nearly done) when the user stops speaking
2. LLM starts the instant the transcript is finalized
3. TTS starts on the first complete sentence, not the full response
4. ESP32 plays the first sentence while the rest is still being generated

---

## Pipeline stages (detailed)

### Stage 1: Streaming Speech-to-Text (STT)

STT runs **during recording**, not after. Audio chunks are forwarded to the STT provider in real-time as they arrive from the ESP32.

| Property | Value |
|----------|-------|
| Input | Opus audio frames from ESP32 (decoded to PCM on backend) |
| Provider | Google Cloud Speech-to-Text streaming API (or Whisper as alternative) |
| Mode | Streaming recognition -- partial results arrive during speech |
| Output | Partial transcripts (interim) + final transcript (on audio:end) |
| Latency | Final transcript ready ~200ms after user stops speaking |

#### How streaming STT works

```
ESP32 sends audio:chunk ──→ Backend decodes Opus ──→ STT streaming session
ESP32 sends audio:chunk ──→ Backend decodes Opus ──→ STT returns partial: "I want to"
ESP32 sends audio:chunk ──→ Backend decodes Opus ──→ STT returns partial: "I want to know the"
ESP32 sends audio:chunk ──→ Backend decodes Opus ──→ STT returns partial: "I want to know the weather"
ESP32 sends audio:end   ──→ Backend closes stream ──→ STT returns final: "I want to know the weather"
                                                       ↓
                                                  [LLM starts immediately]
```

The backend opens a streaming STT session on `audio:start` and feeds it decoded PCM as each `audio:chunk` arrives. By the time the user stops speaking, the STT has already processed most of the audio -- the final transcript is ready in ~200ms instead of ~800ms.

Partial transcripts are sent to the ESP32 for the transcript display mode (see `transcript:partial` event below).

### Stage 2: Streaming Language Model (LLM)

The LLM starts the instant the final STT transcript is ready. It streams its response token-by-token, which feeds into the sentence buffer.

| Property | Value |
|----------|-------|
| Input | Final transcript + system prompt (personality + memories + history) |
| Provider | Gemini API (streaming mode) |
| Context | Personality prompt + top-N relevant memories + recent conversation history |
| Output | Response text streamed token-by-token |
| Latency | First token ~300-500ms, full response 1-3s depending on length |

The system prompt is constructed per-request:

```
[Personality prompt from device config]
[Relevant memories, ordered by confidence]
[Recent conversation history (last 5-10 exchanges)]
[User's current message]
```

### Sentence boundary detection

Between LLM streaming output and TTS, a **sentence buffer** accumulates tokens until a sentence boundary is detected. This is necessary because TTS can't synthesize half a sentence -- it needs a complete thought for natural prosody.

```typescript
// src/ai/sentence-buffer.ts
export class SentenceBuffer {
  private buffer = '';
  private readonly boundaries = /([.!?।。？！])\s+/;

  /**
   * Feed tokens from LLM stream. Returns complete sentences
   * as they become available, keeping incomplete text buffered.
   */
  feed(token: string): string | null {
    this.buffer += token;

    const match = this.buffer.match(this.boundaries);
    if (match) {
      const boundaryIndex = match.index! + match[0].length;
      const sentence = this.buffer.slice(0, boundaryIndex).trim();
      this.buffer = this.buffer.slice(boundaryIndex);
      return sentence;
    }

    return null;
  }

  /** Flush remaining buffer (last sentence may not end with punctuation) */
  flush(): string | null {
    if (this.buffer.trim()) {
      const remaining = this.buffer.trim();
      this.buffer = '';
      return remaining;
    }
    return null;
  }
}
```

Edge cases handled:
- **Short responses** (one sentence): sentence is flushed when LLM stream ends
- **No punctuation**: flushed at stream end as a single sentence
- **Multiple sentences in one token batch**: each extracted and sent to TTS individually
- **Multi-language punctuation**: regex covers Indonesian, English, and common Unicode sentence-enders

### Stage 3: Streaming Text-to-Speech (TTS)

TTS runs **per sentence**, not on the full response. Each sentence from the sentence buffer is synthesized independently and streamed to the ESP32.

| Property | Value |
|----------|-------|
| Input | One sentence at a time from the sentence buffer |
| Provider | Google Cloud Text-to-Speech (or ElevenLabs as alternative) |
| Processing | TTS returns PCM → encode to Opus → stream to ESP32 |
| Output | Opus audio frames sent to ESP32 per sentence |
| Latency | ~300-500ms per sentence (first chunk) |
| Caching | Hash sentence text → cache Opus audio for repeated phrases |

#### TTS queue

Multiple sentences can be in-flight: sentence 1 is being played on ESP32, sentence 2 is being encoded, sentence 3 is being synthesized. A queue manages this:

```
LLM stream → Sentence buffer → TTS queue → Opus encoder → WebSocket → ESP32
                                  ↓
                             [sentence 1] → synthesizing → encoding → sending → playing
                             [sentence 2] → synthesizing → encoding → queued
                             [sentence 3] → waiting
```

---

## Interruption handling

The user can tap the screen while the bot is speaking to interrupt it. This is critical for natural conversation -- you don't want to wait for a long-winded response to finish.

### How it works

```
ESP32: User taps screen during playback
  → ESP32 stops audio playback immediately
  → ESP32 sends audio:interrupt to backend

Backend receives audio:interrupt:
  → Cancel in-flight LLM stream (abort the Gemini request)
  → Cancel pending TTS jobs in the queue
  → Discard unsent audio chunks
  → Send state:update (state: 'idle') to ESP32
  → Store partial response in messages table (mark as interrupted)

If user starts speaking immediately after interrupting:
  → Normal audio:start flow begins
  → LLM context includes the partial response that was interrupted
```

### Why this matters

Without interruption, a 30-second response from Gemini blocks the conversation for 30 seconds. With interruption, the user can cut in at any point -- just like a real conversation.

---

## Conversation session management

The WebSocket protocol needs to know when a conversation starts and ends to properly group exchanges in the database and manage conversation history context.

### Session lifecycle

```
[ESP32 connects via WebSocket]
  ↓
[No active session -- bot is idle]
  ↓
[User taps screen / speaks → audio:start]
  → Backend creates new conversation if none active, or continues existing one
  ↓
[Exchange happens: user speaks → bot responds]
  ↓
[Idle timeout (configurable, default 5 minutes)]
  → Backend closes conversation session (sets ended_at)
  → Next interaction starts a new conversation
```

### Session rules

| Rule | Details |
|------|---------|
| Session start | Created on first `audio:start` when no active session exists |
| Session continues | Subsequent exchanges within the idle timeout are part of the same conversation |
| Session end | Idle timeout (no `audio:start` for N minutes) OR explicit `session:end` from ESP32 |
| Session end on disconnect | If WebSocket disconnects, end the active session after a grace period (30s) |
| History window | LLM context includes messages from the current session only (last 5-10 exchanges) |
| Cross-session context | Memories bridge sessions -- the LLM doesn't see old session transcripts, but it sees extracted memories |

### Why session boundaries matter

- **Database organization:** Conversations in the Flutter app are grouped by session, not as one infinite thread
- **LLM context window management:** Without sessions, the conversation history grows forever and eventually exceeds the token limit
- **Memory extraction:** Triggered at session end, summarizing the entire session for fact extraction

---

## Opus codec

Raw PCM at 16kHz 16-bit mono = **32 KB/s** continuous. Opus encoding reduces this to **~2-4 KB/s** -- roughly 10x bandwidth savings.

### ESP32 side

- **Encoder:** Opus encoder running on ESP32-S3 (the N16R8 has enough RAM/CPU for real-time encoding)
- **Decoder:** Opus decoder for playback of received audio
- **Frame size:** 20ms frames (320 samples at 16kHz = 640 bytes PCM → ~60-120 bytes Opus)
- **Library:** `libopus` compiled for ESP32-S3 via ESP-IDF component

### Backend side

- **Decoder:** Decode incoming Opus frames to PCM before sending to STT
- **Encoder:** Encode TTS output PCM to Opus before sending to ESP32
- **Library:** `@discordjs/opus` or `opusscript` for Node.js

---

## WebSocket protocol

Connection requires `Authorization: DeviceToken <token>` header.

### Events

| Event | Direction | Payload | Description |
|-------|-----------|---------|-------------|
| **Recording** | | | |
| audio:start | ESP → Server | `{ sampleRate: 16000, encoding: 'opus', channels: 1 }` | User started speaking |
| audio:chunk | ESP → Server | Binary Opus frame data | Audio data chunk (streamed to STT in real-time) |
| audio:end | ESP → Server | `{ duration_ms: number }` | User stopped speaking |
| audio:interrupt | ESP → Server | `{}` | User interrupted bot's response (tap during playback) |
| **Transcription** | | | |
| transcript:partial | Server → ESP | `{ text: string, isFinal: false }` | Interim STT result (for display, updates as user speaks) |
| transcript:final | Server → ESP | `{ text: string, isFinal: true }` | Final STT result after audio:end |
| **Response** | | | |
| response:start | Server → ESP | `{ type: 'audio' }` | Bot response beginning |
| response:chunk | Server → ESP | Binary Opus frame data + `cacheKey?: string` | Audio response chunk (sentence by sentence), includes cache key for local SD storage |
| response:text | Server → ESP | `{ text: string, isFinal: boolean }` | Response text (streamed sentence by sentence for display) |
| response:end | Server → ESP | `{ fullText: string, cacheKeys?: { hash: string, sentence: string }[] }` | Bot response complete, includes cache manifest for all sentences |
| **State** | | | |
| state:update | Server → ESP | `{ state: 'listening' \| 'thinking' \| 'speaking' \| 'idle' }` | Backend state change (drives face + servo animation) |
| **Session** | | | |
| session:start | Server → ESP | `{ sessionId: string }` | New conversation session started |
| session:end | Server → ESP | `{ sessionId: string, reason: 'timeout' \| 'disconnect' \| 'manual' }` | Conversation session ended |
| session:end | ESP → Server | `{}` | ESP32 explicitly ends the session (e.g., user long-press) |
| **Presence** | | | |
| presence:arrived | ESP → Server | `{ awayDurationSeconds }` | User's phone detected — user returned to desk |
| presence:departed | ESP → Server | `{}` | User's phone signal lost — user left desk |
| presence:greeting | Server → ESP | `{ text, audio, cacheKey }` | Personalized welcome-back greeting |
| **Proactive** | | | |
| proactive:reminder | Server → ESP | `{ type, text, audio, cacheKey, display }` | Health/wellness reminder with audio and display config |
| proactive:pomodoro | Server → ESP | `{ action, phase, cycle, durationMinutes }` | Pomodoro state change (start/focus/break/stop) |
| proactive:briefing | Server → ESP | `{ text, audio, cacheKey }` | Morning briefing or end-of-day prompt |
| proactive:nudge | Server → ESP | `{ text, audio }` | Idle check-in ("Everything okay?") |
| proactive:dismiss | ESP → Server | `{ type }` | User dismissed a reminder |
| proactive:snooze | ESP → Server | `{ type, snoozeMinutes }` | User snoozed a reminder |
| **Cache** | | | |
| cache:invalidate | Server → ESP | `{ keys: string[] }` | Purge specific cached TTS entries (e.g., voice/language changed) |
| cache:warmup | Server → ESP | `{ entries: { hash: string, audio: Binary }[] }` | Proactively send common phrases to cache during idle |
| **Error** | | | |
| error | Server → ESP | `{ code: string, message: string }` | Error notification |

### New events vs. original

| Added | Why |
|-------|-----|
| `audio:interrupt` | Lets user cut off the bot mid-response |
| `transcript:partial` | Real-time STT feedback for transcript display mode |
| `transcript:final` | Explicit final transcript so ESP32 knows what the bot heard |
| `response:text` | Streamed response text per sentence (display mode, separate from audio) |
| `response:chunk.cacheKey` | Cache key for ESP32 to store TTS audio on MicroSD |
| `response:end.cacheKeys` | Full cache manifest so ESP32 knows what was cacheable |
| `cache:invalidate` | Backend tells ESP32 to purge stale local cache entries |
| `cache:warmup` | Proactively push common phrases to ESP32 cache during idle |
| `session:start/end` | Conversation session lifecycle management |
| `state: 'listening'` | New state -- distinct from idle, drives "listening" face/servo |

### Full message flow (streaming overlap)

```
ESP32                              Backend                         External APIs
  |                                  |                               |
  |== RECORDING PHASE ===============|                               |
  |-- audio:start ------------------>|                               |
  |                                  |-- open STT stream ----------->|
  |-- audio:chunk ------------------>|-- decode Opus, feed STT ----->|
  |<---------- state:update ---------|  (state: 'listening')         |
  |                                  |<-- STT partial: "I want" ----|
  |<-- transcript:partial -----------|                               |
  |-- audio:chunk ------------------>|-- feed STT ------------------>|
  |                                  |<-- STT partial: "I want to"--|
  |<-- transcript:partial -----------|                               |
  |-- audio:chunk ------------------>|-- feed STT ------------------>|
  |-- audio:end -------------------->|-- close STT stream ---------->|
  |                                  |<-- STT final transcript ------|
  |<-- transcript:final -------------|                               |
  |                                  |                               |
  |== THINKING PHASE ================|                               |
  |<---------- state:update ---------|  (state: 'thinking')          |
  |                                  |-- fetch memories              |
  |                                  |-- build system prompt         |
  |                                  |-- start LLM stream ---------->|
  |                                  |                               |
  |== STREAMING RESPONSE PHASE ======|                               |
  |                                  |<-- LLM tokens: "The weather" -|
  |                                  |<-- LLM tokens: " in Jakarta"  |
  |                                  |<-- LLM tokens: " is sunny."   |
  |                                  |   [sentence 1 complete]       |
  |                                  |-- TTS sentence 1 ------------>|
  |                                  |<-- TTS audio for sentence 1 --|
  |<---------- response:start ------|                               |
  |<---------- state:update ---------|  (state: 'speaking')          |
  |<-- response:text (sentence 1) ---|                               |
  |<-- response:chunk (Opus audio) --|   [ESP32 starts playing]      |
  |                                  |                               |
  |                                  |<-- LLM tokens: "It's about"   |
  |                                  |<-- LLM tokens: " 32 degrees." |
  |                                  |   [sentence 2 complete]       |
  |                                  |-- TTS sentence 2 ------------>|
  |                                  |<-- TTS audio for sentence 2 --|
  |<-- response:text (sentence 2) ---|                               |
  |<-- response:chunk (Opus audio) --|   [ESP32 queues for playback] |
  |                                  |                               |
  |                                  |<-- LLM stream ends            |
  |                                  |   [flush sentence buffer]     |
  |                                  |-- TTS final sentence -------->|
  |                                  |<-- TTS audio ----------------|
  |<-- response:text (final) --------|                               |
  |<-- response:chunk (Opus audio) --|                               |
  |<---------- response:end ---------|                               |
  |   [ESP32 finishes playback]      |                               |
  |<---------- state:update ---------|  (state: 'idle')              |
  |                                  |                               |
  |== INTERRUPTION (if user taps) ===|                               |
  |-- audio:interrupt --------------->|                               |
  |                                  |-- cancel LLM stream           |
  |                                  |-- cancel TTS queue            |
  |<---------- state:update ---------|  (state: 'idle')              |
  |                                  |-- store partial response      |
```

---

## Latency budget (with streaming overlap)

Target: **< 1.5 seconds** from user stops speaking to first audio response.

### Best case (streaming overlap)

| Stage | Time | Overlapped? | Notes |
|-------|------|-------------|-------|
| STT (during recording) | 0ms added | Yes -- runs during speech | Final transcript ready ~200ms after audio:end |
| STT finalization | ~200ms | -- | Remaining processing after audio:end |
| LLM first token | ~300-500ms | -- | Gemini streaming, time to first token |
| LLM to first sentence boundary | ~200-500ms | -- | Depends on response length |
| TTS first sentence | ~300-500ms | -- | Google TTS for one sentence |
| Opus encode | ~10ms | Negligible | |
| Network (Backend → ESP) | ~50ms | -- | WebSocket |
| **Total to first audio** | **~1.1-1.8s** | | **~50% faster than sequential** |

### Comparison with sequential approach

| Approach | Time to first audio | Why |
|----------|-------------------|-----|
| Sequential (naive) | ~2.9-4.0s | Each stage waits for previous to fully complete |
| Streaming overlap | ~1.1-1.8s | STT during speech, LLM→TTS per sentence |
| Gemini multimodal (theoretical) | ~0.8-1.2s | Single API call, but black box and not swappable |

The streaming overlap approach gets us close to multimodal API latency while keeping the pipeline debuggable and swappable.

---

## Backend pipeline implementation

The `AiService` orchestrator needs to change from a simple sequential flow to a streaming pipeline. Here's the updated architecture:

```typescript
// src/ai/ai.service.ts (streaming pipeline)
@Injectable()
export class AiService {
  constructor(
    @Inject(STT_PROVIDER) private stt: ISttProvider,
    @Inject(LLM_PROVIDER) private llm: ILlmProvider,
    @Inject(TTS_PROVIDER) private tts: ITtsProvider,
    @Inject(AUDIO_CODEC) private codec: IAudioCodec,
    private prompt: PromptService,
    private memories: MemoriesService,
    private sentenceBuffer: SentenceBuffer,
  ) {}

  /**
   * Process a complete exchange: final transcript → streamed audio response.
   * Yields audio chunks and text as they become available.
   */
  async *processTranscript(
    deviceId: string,
    transcript: string,
    personality: PersonalityConfig,
    history: Message[],
  ): AsyncGenerator<PipelineEvent> {
    // 1. Build prompt with memories
    const memories = await this.memories.getRelevant(deviceId);
    const systemPrompt = this.prompt.buildSystemPrompt(personality, memories);
    const messages = this.prompt.buildMessages(history, transcript);

    // 2. Stream LLM response, buffer into sentences, TTS each sentence
    const llmStream = this.llm.generateStream(systemPrompt, messages);
    let fullResponseText = '';

    for await (const token of llmStream) {
      fullResponseText += token;

      const sentence = this.sentenceBuffer.feed(token);
      if (sentence) {
        // 3. TTS the completed sentence
        const pcmAudio = await this.tts.synthesize(sentence, {
          language: personality.language,
        });
        const opusAudio = this.codec.encode(pcmAudio);

        yield { type: 'text', text: sentence };
        yield { type: 'audio', data: opusAudio };
      }
    }

    // 4. Flush remaining text in sentence buffer
    const remaining = this.sentenceBuffer.flush();
    if (remaining) {
      const pcmAudio = await this.tts.synthesize(remaining, {
        language: personality.language,
      });
      const opusAudio = this.codec.encode(pcmAudio);

      yield { type: 'text', text: remaining };
      yield { type: 'audio', data: opusAudio };
    }

    // 5. Bump memory access timestamps
    await this.memories.bumpAccessed(memories.map((m) => m.id));

    yield { type: 'done', fullText: fullResponseText };
  }
}

type PipelineEvent =
  | { type: 'text'; text: string }
  | { type: 'audio'; data: Buffer }
  | { type: 'done'; fullText: string };
```

### Updated interfaces

The `ISttProvider` interface needs a streaming variant:

```typescript
// Addition to src/ai/interfaces/stt-provider.interface.ts
export interface ISttProvider {
  // Existing: batch transcription
  transcribe(pcmAudio: Buffer, options?: SttOptions): Promise<SttResult>;

  // New: streaming transcription
  createStream(options?: SttOptions): SttStream;
}

export interface SttStream {
  /** Feed audio chunks as they arrive */
  write(pcmChunk: Buffer): void;

  /** Signal end of audio */
  end(): void;

  /** Emits partial and final transcript results */
  on(event: 'partial', listener: (text: string) => void): void;
  on(event: 'final', listener: (result: SttResult) => void): void;
  on(event: 'error', listener: (error: Error) => void): void;

  /** Cancel the stream */
  destroy(): void;
}
```

---

## ESP32 audio playback buffer

Since audio arrives sentence-by-sentence (not all at once), the ESP32 needs a small playback queue:

```
Incoming Opus chunks → [Decode queue] → [PCM playback ring buffer] → I2S speaker

Behavior:
  - Chunks arrive per sentence, may have small gaps between sentences
  - Ring buffer smooths out gaps -- if buffer runs empty, insert brief silence
  - Buffer target: 200-500ms of audio ahead of playback position
  - If buffer overflows (backend sending faster than playback): drop oldest, log warning
```

This is a firmware concern -- see [05-firmware.md](05-firmware.md) for I2S task details.

---

## Error handling in the pipeline

| Failure point | What happens | Recovery |
|---------------|-------------|----------|
| STT stream fails mid-recording | Send error event to ESP32, close STT stream | ESP32 shows error face, user can retry |
| STT returns empty transcript | Skip LLM/TTS, send error event | ESP32 shows confused face: "I didn't catch that" |
| LLM stream fails mid-response | Send whatever was already TTS'd, then error event | Partial response plays, then error indication |
| LLM returns empty response | Send error event | ESP32 shows confused face |
| TTS fails for one sentence | Skip that sentence's audio, continue with next | Graceful degradation -- some audio still plays |
| TTS fails completely | Send response:end with text only (no audio) | ESP32 shows transcript on screen instead |
| WebSocket disconnects mid-pipeline | Cancel all in-flight processing, end session | ESP32 auto-reconnects, session ends |
| Interruption during pipeline | Cancel LLM stream, cancel TTS queue, store partial | Clean shutdown, ready for next exchange |

---

## Related docs

- [01-architecture.md](01-architecture.md) — Where the audio pipeline fits in the system
- [05-firmware.md](05-firmware.md) — ESP32 I2S, playback buffer, and Opus implementation details
- [06-backend-api.md](06-backend-api.md) — WebSocket gateway implementation and ports/adapters pattern
