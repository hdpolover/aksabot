# 06 — Backend API

---

## Overview

NestJS backend serving two interfaces:
1. **WebSocket gateway** — real-time audio streaming with ESP32 devices
2. **REST API** — data management for the Flutter companion app

---

## Tech stack

| Component | Technology |
|-----------|-----------|
| Framework | NestJS |
| Database | PostgreSQL |
| ORM | TypeORM |
| WebSocket | @nestjs/websockets (Socket.IO or ws) |
| Auth | @nestjs/jwt, bcrypt, passport |
| Validation | class-validator, class-transformer |
| AI / LLM | @google/generative-ai (Gemini SDK — direct, no LangChain) |
| STT | @google-cloud/speech |
| TTS | @google-cloud/text-to-speech |
| Audio codec | @discordjs/opus or opusscript (Opus encode/decode) |

### Why no LangChain

The LLM usage in this project is a single call pattern: system prompt (personality + memories + history) + user message → response. LangChain adds dependency bloat and API churn for something that's ~20 lines with the Gemini SDK directly. We get the same swap-ability through our own interface abstractions (see Ports and Adapters section below) without the third-party abstraction tax.

---

## WebSocket gateway

### Connection

- Endpoint: `wss://<host>/ws`
- Auth: `Authorization: DeviceToken <token>` header on connection
- Invalid/revoked token -> connection rejected (401)
- One active connection per device (new connection closes old one)

### Events

See [04-audio-pipeline.md](04-audio-pipeline.md) for the full protocol specification.

### Gateway responsibilities

1. Validate device token on connection
2. Buffer incoming Opus audio chunks
3. On `audio:end`: trigger the decoupled AI pipeline (STT -> LLM -> TTS)
4. Stream Opus response chunks back to device
5. Send `state:update` events to drive face animations
6. Update `devices.last_seen_at` on connection
7. Store conversation and messages in database after each exchange

---

## REST API

All endpoints require `Authorization: Bearer <jwt>` except `/auth/*` routes.

Responses follow a consistent shape:

```json
{
  "data": { ... },
  "meta": { "page": 1, "limit": 20, "total": 42 }
}
```

Errors:

```json
{
  "statusCode": 400,
  "message": "Validation failed",
  "errors": [{ "field": "email", "message": "must be a valid email" }]
}
```

---

### Auth endpoints

| Method | Endpoint | Body | Response | Description |
|--------|----------|------|----------|-------------|
| POST | /auth/register | `{ email, password, name }` | `{ accessToken, refreshToken, user }` | Create account |
| POST | /auth/login | `{ email, password }` | `{ accessToken, refreshToken, user }` | Login |
| POST | /auth/refresh | `{ refreshToken }` | `{ accessToken, refreshToken }` | Refresh tokens |

---

### Device endpoints

All scoped to the authenticated user -- a user can only see/manage their own devices.

| Method | Endpoint | Body/Params | Response | Description |
|--------|----------|-------------|----------|-------------|
| POST | /devices | `{ name? }` | `{ device, deviceToken }` | Register new device |
| GET | /devices | -- | `{ devices[] }` | List user's devices |
| GET | /devices/:id | -- | `{ device }` | Get device details |
| PATCH | /devices/:id/settings | `{ volume?, brightness?, display_transcript?, idle_timeout_seconds? }` | `{ device }` | Update settings |
| DELETE | /devices/:id | -- | 204 | Remove device, revoke token |

**POST /devices** generates a crypto-random device token. The token is returned once and must be written to the ESP32 via BLE. It is not retrievable again (only revocable).

---

### Conversation endpoints

| Method | Endpoint | Params | Response | Description |
|--------|----------|--------|----------|-------------|
| GET | /devices/:id/conversations | `?page=1&limit=20` | `{ conversations[], meta }` | List conversations (paginated, newest first) |
| GET | /conversations/:id/messages | `?page=1&limit=50` | `{ messages[], meta }` | Get messages in a conversation |

---

### Memory endpoints

| Method | Endpoint | Body | Response | Description |
|--------|----------|------|----------|-------------|
| GET | /devices/:id/memories | `?category=personal` | `{ memories[] }` | List memories (filterable by category) |
| PUT | /memories/:id | `{ fact?, category? }` | `{ memory }` | Edit a memory |
| DELETE | /memories/:id | -- | 204 | Delete a memory |

---

### Personality endpoints

| Method | Endpoint | Body | Response | Description |
|--------|----------|------|----------|-------------|
| GET | /devices/:id/personality | -- | `{ personality }` | Get personality config |
| PUT | /devices/:id/personality | `{ name?, tone?, language?, system_prompt? }` | `{ personality }` | Update personality |

---

### OTA endpoint

| Method | Endpoint | Body | Response | Description |
|--------|----------|------|----------|-------------|
| POST | /devices/:id/ota | `{ firmware_url }` | `{ status }` | Trigger OTA update |

---

### Reminder endpoints

| Method | Endpoint | Body | Response | Description |
|--------|----------|------|----------|-------------|
| GET | /devices/:id/reminders | — | `{ reminders }` | Get current reminder config |
| PUT | /devices/:id/reminders | `{ standUp?, hydration?, eyeBreak?, stretch?, posture?, endOfDay?, morningBriefing?, idleNudge? }` | `{ reminders }` | Update reminder config |

### Pomodoro endpoints

| Method | Endpoint | Body | Response | Description |
|--------|----------|------|----------|-------------|
| POST | /devices/:id/pomodoro/start | — | `{ pomodoro }` | Start pomodoro session |
| POST | /devices/:id/pomodoro/stop | — | 204 | Stop pomodoro session |
| GET | /devices/:id/pomodoro | — | `{ pomodoro }` | Get current pomodoro state (phase, cycle, time remaining) |

### Focus mode endpoints

| Method | Endpoint | Body | Response | Description |
|--------|----------|------|----------|-------------|
| POST | /devices/:id/focus | `{ durationMinutes }` | `{ focus }` | Start focus mode |
| DELETE | /devices/:id/focus | — | 204 | End focus mode |

---

## Ports and Adapters (abstraction layer)

The backend follows a **Ports and Adapters** pattern. Business logic depends on interfaces (ports), never on concrete SDKs. Swapping a provider means writing a new adapter class and changing one line in the module config.

### Why this matters

The AI provider space moves fast — pricing changes, new models drop, services go down. Without interfaces, swapping Google STT for Whisper means rewriting the orchestrator. With interfaces, you write one new file and rebind the injection token.

### Injection tokens

NestJS uses string/symbol tokens to resolve interfaces at runtime:

```typescript
// src/ai/interfaces/tokens.ts
export const STT_PROVIDER = Symbol('STT_PROVIDER');
export const LLM_PROVIDER = Symbol('LLM_PROVIDER');
export const TTS_PROVIDER = Symbol('TTS_PROVIDER');
export const AUDIO_CODEC = Symbol('AUDIO_CODEC');
```

---

## Interface definitions (ports)

These are the contracts. The orchestrator and all business logic depend only on these.

### ISttProvider

```typescript
// src/ai/interfaces/stt-provider.interface.ts
export interface SttOptions {
  sampleRate?: number;
  languages?: string[];
}

export interface SttResult {
  transcript: string;
  confidence: number;
  language?: string;
}

export interface SttStream {
  /** Feed audio chunks as they arrive from the ESP32 */
  write(pcmChunk: Buffer): void;
  /** Signal end of audio input */
  end(): void;
  /** Listen for partial and final transcript results */
  on(event: 'partial', listener: (text: string) => void): void;
  on(event: 'final', listener: (result: SttResult) => void): void;
  on(event: 'error', listener: (error: Error) => void): void;
  /** Cancel the stream (used on interruption or error) */
  destroy(): void;
}

export interface ISttProvider {
  /** Batch transcription (for testing or fallback) */
  transcribe(pcmAudio: Buffer, options?: SttOptions): Promise<SttResult>;
  /** Streaming transcription (primary — runs during recording) */
  createStream(options?: SttOptions): SttStream;
}
```

### ILlmProvider

```typescript
// src/ai/interfaces/llm-provider.interface.ts
export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface LlmResponse {
  text: string;
  tokensUsed?: { prompt: number; completion: number };
}

export interface ILlmProvider {
  generate(systemPrompt: string, messages: ChatMessage[]): Promise<LlmResponse>;
  generateStream(systemPrompt: string, messages: ChatMessage[]): AsyncGenerator<string>;
}
```

### ITtsProvider

```typescript
// src/ai/interfaces/tts-provider.interface.ts
export interface ITtsProvider {
  synthesize(text: string, options?: { language?: string; voice?: string }): Promise<Buffer>;
}
```

### IAudioCodec

```typescript
// src/ai/interfaces/audio-codec.interface.ts
export interface IAudioCodec {
  encode(pcm: Buffer): Buffer;
  decode(encoded: Buffer): Buffer;
}
```

---

## Adapter implementations

Each adapter is a thin wrapper around a specific SDK. It implements the port interface and handles all provider-specific logic internally.

### GoogleSttProvider (implements ISttProvider)

```typescript
// src/ai/adapters/google-stt.provider.ts
@Injectable()
export class GoogleSttProvider implements ISttProvider {
  private client: SpeechClient;

  constructor() {
    this.client = new SpeechClient();
  }

  /** Batch transcription (fallback / testing) */
  async transcribe(pcmAudio: Buffer, options?: SttOptions): Promise<SttResult> {
    const [response] = await this.client.recognize({
      audio: { content: pcmAudio.toString('base64') },
      config: this.buildConfig(options),
    });

    const best = response.results?.[0]?.alternatives?.[0];
    return {
      transcript: response.results?.map((r) => r.alternatives?.[0]?.transcript).join(' ') ?? '',
      confidence: best?.confidence ?? 0,
      language: response.results?.[0]?.languageCode,
    };
  }

  /** Streaming transcription (primary — runs during recording) */
  createStream(options?: SttOptions): SttStream {
    const recognizeStream = this.client.streamingRecognize({
      config: this.buildConfig(options),
      interimResults: true,  // return partial transcripts as user speaks
    });

    return {
      write(pcmChunk: Buffer) {
        recognizeStream.write({ audioContent: pcmChunk });
      },
      end() {
        recognizeStream.end();
      },
      on(event: string, listener: (...args: any[]) => void) {
        if (event === 'partial' || event === 'final') {
          recognizeStream.on('data', (response: any) => {
            const result = response.results?.[0];
            if (!result) return;
            const transcript = result.alternatives?.[0]?.transcript ?? '';
            if (event === 'final' && result.isFinal) {
              listener({
                transcript,
                confidence: result.alternatives?.[0]?.confidence ?? 0,
                language: result.languageCode,
              });
            } else if (event === 'partial' && !result.isFinal) {
              listener(transcript);
            }
          });
        } else if (event === 'error') {
          recognizeStream.on('error', listener);
        }
      },
      destroy() {
        recognizeStream.destroy();
      },
    };
  }

  private buildConfig(options?: SttOptions) {
    return {
      encoding: 'LINEAR16' as const,
      sampleRateHertz: options?.sampleRate ?? 16000,
      languageCode: options?.languages?.[0] ?? 'id-ID',
      alternativeLanguageCodes: options?.languages?.slice(1) ?? ['en-US'],
    };
  }
}
```

### GeminiLlmProvider (implements ILlmProvider)

```typescript
// src/ai/adapters/gemini-llm.provider.ts
@Injectable()
export class GeminiLlmProvider implements ILlmProvider {
  private model: GenerativeModel;

  constructor(private config: ConfigService) {
    const genAI = new GoogleGenerativeAI(config.get('GEMINI_API_KEY'));
    this.model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
  }

  async generate(systemPrompt: string, messages: ChatMessage[]): Promise<LlmResponse> {
    const chat = this.model.startChat({
      systemInstruction: systemPrompt,
      history: messages.slice(0, -1).map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      })),
    });

    const result = await chat.sendMessage(messages.at(-1).content);
    const usage = result.response.usageMetadata;

    return {
      text: result.response.text(),
      tokensUsed: usage
        ? { prompt: usage.promptTokenCount, completion: usage.candidatesTokenCount }
        : undefined,
    };
  }

  async *generateStream(systemPrompt: string, messages: ChatMessage[]): AsyncGenerator<string> {
    const chat = this.model.startChat({
      systemInstruction: systemPrompt,
      history: messages.slice(0, -1).map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      })),
    });

    const result = await chat.sendMessageStream(messages.at(-1).content);
    for await (const chunk of result.stream) {
      yield chunk.text();
    }
  }
}
```

### GoogleTtsProvider (implements ITtsProvider)

```typescript
// src/ai/adapters/google-tts.provider.ts
@Injectable()
export class GoogleTtsProvider implements ITtsProvider {
  private client: TextToSpeechClient;

  constructor() {
    this.client = new TextToSpeechClient();
  }

  async synthesize(text: string, options?: { language?: string; voice?: string }): Promise<Buffer> {
    const [response] = await this.client.synthesizeSpeech({
      input: { text },
      voice: {
        languageCode: options?.language ?? 'id-ID',
        name: options?.voice,
        ssmlGender: 'NEUTRAL',
      },
      audioConfig: { audioEncoding: 'LINEAR16', sampleRateHertz: 16000 },
    });

    return Buffer.from(response.audioContent as Uint8Array);
  }
}
```

### OpusAudioCodec (implements IAudioCodec)

```typescript
// src/ai/adapters/opus-audio.codec.ts
@Injectable()
export class OpusAudioCodec implements IAudioCodec {
  private encoder: OpusEncoder;
  private decoder: OpusEncoder;

  constructor() {
    // 16kHz, 1 channel
    this.encoder = new OpusEncoder(16000, 1);
    this.decoder = new OpusEncoder(16000, 1);
  }

  encode(pcm: Buffer): Buffer {
    return this.encoder.encode(pcm);
  }

  decode(encoded: Buffer): Buffer {
    return this.decoder.decode(encoded);
  }
}
```

---

## Prompt service

The prompt service is not behind an interface — it's internal business logic, not an external provider. It constructs the system prompt from personality config, memories, and conversation history.

```typescript
// src/ai/prompt.service.ts
@Injectable()
export class PromptService {
  buildSystemPrompt(personality: PersonalityConfig, memories: Memory[]): string {
    const memoryBlock = memories
      .map((m) => `- ${m.fact} (${m.category})`)
      .join('\n');

    return `${personality.system_prompt}

You know the following about the user:
${memoryBlock}

Respond in ${personality.language || 'the same language the user uses'}.
Keep responses concise and natural for voice conversation.`;
  }

  buildMessages(history: Message[], userMessage: string): ChatMessage[] {
    return [
      ...history.map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content })),
      { role: 'user' as const, content: userMessage },
    ];
  }
}
```

---

## Pipeline orchestrator

`AiService` is the single entry point the WebSocket gateway calls. It depends only on interfaces via injection tokens — it has no knowledge of which concrete providers are in use.

The orchestrator exposes two capabilities:
1. **`createSttStream()`** — returns a streaming STT session for real-time transcription during recording
2. **`processTranscript()`** — takes a final transcript and yields streamed audio/text response events

These are separate because STT runs during recording (managed by the gateway), while the LLM→TTS pipeline runs after the transcript is finalized.

```typescript
// src/ai/ai.service.ts
type PipelineEvent =
  | { type: 'text'; text: string }
  | { type: 'audio'; data: Buffer }
  | { type: 'done'; fullText: string };

@Injectable()
export class AiService {
  constructor(
    @Inject(STT_PROVIDER) private stt: ISttProvider,
    @Inject(LLM_PROVIDER) private llm: ILlmProvider,
    @Inject(TTS_PROVIDER) private tts: ITtsProvider,
    @Inject(AUDIO_CODEC) private codec: IAudioCodec,
    private prompt: PromptService,
    private memories: MemoriesService,
  ) {}

  /**
   * Create a streaming STT session. The gateway feeds audio chunks
   * into this during recording and receives partial/final transcripts.
   */
  createSttStream(options?: SttOptions): SttStream {
    return this.stt.createStream(options);
  }

  /**
   * Decode a single Opus chunk to PCM (used by gateway to feed STT stream).
   */
  decodeAudio(opusChunk: Buffer): Buffer {
    return this.codec.decode(opusChunk);
  }

  /**
   * Process a finalized transcript into a streamed audio response.
   * Yields events as they become available:
   *   - { type: 'text', text } — a completed sentence (for display)
   *   - { type: 'audio', data } — Opus audio for that sentence (for playback)
   *   - { type: 'done', fullText } — pipeline complete
   *
   * The caller (gateway) can abort by breaking out of the generator,
   * which handles the interruption case.
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
    const sentenceBuffer = new SentenceBuffer();
    const llmStream = this.llm.generateStream(systemPrompt, messages);
    let fullResponseText = '';

    for await (const token of llmStream) {
      fullResponseText += token;

      const sentence = sentenceBuffer.feed(token);
      if (sentence) {
        // 3. TTS the completed sentence → encode to Opus
        const pcmAudio = await this.tts.synthesize(sentence, {
          language: personality.language,
        });
        const opusAudio = this.codec.encode(pcmAudio);

        yield { type: 'text', text: sentence };
        yield { type: 'audio', data: opusAudio };
      }
    }

    // 4. Flush remaining text in sentence buffer
    const remaining = sentenceBuffer.flush();
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
```

### How the gateway uses the orchestrator

```typescript
// Simplified — inside audio.gateway.ts

// During recording: stream STT
const sttStream = this.aiService.createSttStream({ languages: ['id-ID', 'en-US'] });

socket.on('audio:chunk', (opusData: Buffer) => {
  const pcm = this.aiService.decodeAudio(opusData);
  sttStream.write(pcm);
});

sttStream.on('partial', (text) => {
  socket.emit('transcript:partial', { text, isFinal: false });
});

socket.on('audio:end', () => {
  sttStream.end();
});

sttStream.on('final', async (result) => {
  socket.emit('transcript:final', { text: result.transcript, isFinal: true });
  socket.emit('state:update', { state: 'thinking' });

  // After transcript finalized: stream LLM → TTS response
  const pipeline = this.aiService.processTranscript(
    device.id, result.transcript, device.personality, sessionHistory,
  );

  let started = false;
  for await (const event of pipeline) {
    // Check for interruption
    if (this.isInterrupted(device.id)) {
      break;  // breaking out of the generator cancels the pipeline
    }

    if (event.type === 'text') {
      socket.emit('response:text', { text: event.text, isFinal: false });
    } else if (event.type === 'audio') {
      if (!started) {
        socket.emit('response:start', { type: 'audio' });
        socket.emit('state:update', { state: 'speaking' });
        started = true;
      }
      socket.emit('response:chunk', event.data);
    } else if (event.type === 'done') {
      socket.emit('response:text', { text: event.fullText, isFinal: true });
      socket.emit('response:end', { fullText: event.fullText });
      socket.emit('state:update', { state: 'idle' });
    }
  }
});

// Interruption handler
socket.on('audio:interrupt', () => {
  this.markInterrupted(device.id);
  socket.emit('state:update', { state: 'idle' });
});
```

---

## Module wiring

This is where the binding happens. Swapping a provider is a one-line change here.

```typescript
// src/ai/ai.module.ts
@Module({
  imports: [MemoriesModule],
  providers: [
    // Ports -> Adapters binding (swap providers here)
    { provide: STT_PROVIDER, useClass: GoogleSttProvider },
    { provide: LLM_PROVIDER, useClass: GeminiLlmProvider },
    { provide: TTS_PROVIDER, useClass: GoogleTtsProvider },
    { provide: AUDIO_CODEC, useClass: OpusAudioCodec },

    // Internal services (not behind interfaces — they're business logic, not external)
    PromptService,
    AiService,
  ],
  exports: [AiService],
})
export class AiModule {}
```

`SentenceBuffer` is not a NestJS provider — it's instantiated per-pipeline-run inside `AiService.processTranscript()` since each exchange needs its own buffer state.

### How to swap a provider

Example: swap Google STT for OpenAI Whisper.

1. Create `src/ai/adapters/whisper-stt.provider.ts` implementing `ISttProvider`
2. Change one line in `ai.module.ts`:

```typescript
// Before
{ provide: STT_PROVIDER, useClass: GoogleSttProvider },
// After
{ provide: STT_PROVIDER, useClass: WhisperSttProvider },
```

That's it. The orchestrator, prompt service, gateway, and every other module remain untouched.

---

## NestJS module structure

```
src/
  ai/
    interfaces/
      tokens.ts                  -- injection token symbols
      stt-provider.interface.ts  -- ISttProvider + SttStream ports
      llm-provider.interface.ts  -- ILlmProvider port
      tts-provider.interface.ts  -- ITtsProvider port
      audio-codec.interface.ts   -- IAudioCodec port
    adapters/
      google-stt.provider.ts     -- ISttProvider <- Google Cloud Speech (batch + streaming)
      gemini-llm.provider.ts     -- ILlmProvider <- Gemini SDK (batch + streaming)
      google-tts.provider.ts     -- ITtsProvider <- Google Cloud TTS
      opus-audio.codec.ts        -- IAudioCodec  <- Opus via @discordjs/opus
    ai.module.ts                 -- binds ports to adapters
    ai.service.ts                -- streaming pipeline orchestrator (depends on ports only)
    prompt.service.ts            -- system prompt builder (internal logic)
    sentence-buffer.ts           -- LLM token stream -> sentence boundary detection
  auth/
    auth.module.ts
    auth.controller.ts
    auth.service.ts
    jwt.strategy.ts
    device-token.guard.ts
  devices/
    devices.module.ts
    devices.controller.ts
    devices.service.ts
  conversations/
    conversations.module.ts
    conversations.controller.ts
    conversations.service.ts
  memories/
    memories.module.ts
    memories.controller.ts
    memories.service.ts
  scheduler/
    scheduler.module.ts            -- scheduler module
    scheduler.service.ts           -- per-device timer management (start/stop on connect/disconnect)
    reminder.service.ts            -- serves reminders from response pool + TTS cache
    response-pool.service.ts       -- LRU retrieval, batch generation, background refill
    pomodoro.service.ts            -- pomodoro state machine per device
    reminder.types.ts              -- ReminderType, ReminderConfig, PomodoroState types
  gateway/
    audio.gateway.ts               -- WebSocket gateway (depends on AiService + SchedulerService)
    audio.gateway.module.ts
  database/
    entities/                      -- TypeORM entities
    migrations/
```

---

## Caching and efficiency

### Architecture overview

Two caching layers with different purposes:

```
                        ┌─────────────────────────────────────┐
                        │          NestJS Backend              │
ESP32                   │                                      │
  ┌──────────┐          │  ┌───────────┐    ┌──────────────┐  │
  │ MicroSD  │◄─────────│──│ Redis     │    │ In-memory    │  │
  │ TTS cache│  cache    │  │           │    │ (NestJS)     │  │
  │ (local)  │  hints    │  │ • TTS     │    │ • Device cfg │  │
  └──────────┘          │  │ • Session  │    │ • Memories   │  │
                        │  │ • Rate lim │    │ • Personality│  │
                        │  └───────────┘    └──────────────┘  │
                        │                                      │
                        │  ┌──────────────┐                   │
                        │  │ PostgreSQL   │                   │
                        │  │ (source of   │                   │
                        │  │  truth)      │                   │
                        │  └──────────────┘                   │
                        └─────────────────────────────────────┘
```

| Layer | Technology | What it caches | Why |
|-------|-----------|---------------|-----|
| **ESP32 MicroSD** | FAT32 files | TTS audio (Opus files), resilience audio | Zero-latency playback for cached responses, works offline |
| **Redis** | Redis 7+ | TTS audio (PCM), session state, rate counters, usage stats | TTS is the most expensive API call — caching saves money and latency |
| **In-memory** | @nestjs/cache-manager | Device config, personality, memories per device | Low-cardinality, read-heavy, invalidated on write |
| **PostgreSQL** | — | Nothing cached — it IS the source of truth | Conversations, messages, users, devices, memories |

### Redis

Redis handles three concerns that don't belong in PostgreSQL or in-memory:

#### 1. TTS response cache (cost saver)

The most impactful cache. TTS API charges per character and adds latency. Many responses contain repeated phrases.

```typescript
// src/ai/interfaces/tts-cache.interface.ts
export const TTS_CACHE = Symbol('TTS_CACHE');

export interface ITtsCache {
  get(key: string): Promise<Buffer | null>;
  set(key: string, audio: Buffer, ttlSeconds?: number): Promise<void>;
  generateKey(text: string, language: string, voice?: string): string;
}
```

```typescript
// src/ai/adapters/redis-tts-cache.ts
@Injectable()
export class RedisTtsCache implements ITtsCache {
  constructor(@Inject('REDIS_CLIENT') private redis: Redis) {}

  generateKey(text: string, language: string, voice?: string): string {
    const input = `${text}|${language}|${voice ?? 'default'}`;
    return `tts:${createHash('sha256').update(input).digest('hex')}`;
  }

  async get(key: string): Promise<Buffer | null> {
    const data = await this.redis.getBuffer(key);
    return data;
  }

  async set(key: string, audio: Buffer, ttlSeconds = 86400 * 7): Promise<void> {
    await this.redis.setex(key, ttlSeconds, audio);
  }
}
```

The TTS adapter is wrapped with cache logic in the pipeline orchestrator:

```typescript
// Inside AiService.processTranscript() — TTS step becomes:
const cacheKey = this.ttsCache.generateKey(sentence, personality.language);
let pcmAudio = await this.ttsCache.get(cacheKey);

if (!pcmAudio) {
  // Cache MISS — call TTS API
  pcmAudio = await this.tts.synthesize(sentence, { language: personality.language });
  await this.ttsCache.set(cacheKey, pcmAudio);
}

const opusAudio = this.codec.encode(pcmAudio);

// Include cache key in response so ESP32 can cache locally too
yield { type: 'audio', data: opusAudio, cacheKey };
```

**TTL:** 7 days default. Eviction is handled by Redis key expiry — no manual cleanup needed.

**Cache key:** SHA-256 hash of `text|language|voice`. Same text in different languages = different cache entries.

#### 2. WebSocket session state

Active session data that is ephemeral (doesn't belong in PostgreSQL) but needs to survive gateway restarts:

```typescript
// Session state stored in Redis
interface DeviceSession {
  deviceId: string;
  userId: string;
  conversationId: string | null;    // active conversation
  state: 'idle' | 'listening' | 'thinking' | 'speaking';
  interrupted: boolean;              // interruption flag
  connectedAt: string;               // ISO timestamp
  lastActivityAt: string;
}

// Redis key: session:<deviceId>
// TTL: 1 hour (auto-cleanup if device disconnects without clean close)
```

Why Redis and not in-memory: if the NestJS process restarts (deploy, crash), in-memory session state is lost. The ESP32 reconnects but the backend doesn't know it was mid-conversation. Redis survives restarts.

#### 3. Rate limiting counters

```typescript
// Redis key patterns:
//   ratelimit:auth:<ip>         — auth endpoint rate limit (5/min)
//   ratelimit:api:<userId>      — REST API rate limit (60/min)
//   ratelimit:ws:<deviceId>     — WebSocket conversation rate limit (10/min)
//   usage:<deviceId>:daily      — daily conversation count (for cost tracking)
//   usage:<deviceId>:monthly    — monthly conversation count

// Using Redis INCR + EXPIRE for sliding window counters
```

#### Redis module wiring

```typescript
// src/cache/cache.module.ts
@Module({
  providers: [
    {
      provide: 'REDIS_CLIENT',
      useFactory: (config: ConfigService) => {
        return new Redis({
          host: config.get('REDIS_HOST', 'localhost'),
          port: config.get('REDIS_PORT', 6379),
          password: config.get('REDIS_PASSWORD'),
        });
      },
      inject: [ConfigService],
    },
    { provide: TTS_CACHE, useClass: RedisTtsCache },
  ],
  exports: ['REDIS_CLIENT', TTS_CACHE],
})
export class CacheModule {}
```

### In-memory cache (NestJS)

For data that is read on every WebSocket exchange but rarely changes:

| Data | Read frequency | Write frequency | TTL | Invalidation |
|------|---------------|-----------------|-----|-------------|
| Device config + personality | Every exchange | User edits via app (rare) | 5 min | Invalidate on PATCH /devices/:id |
| Device memories (top N) | Every exchange | After conversation ends | 2 min | Invalidate on memory extraction or user edit |

```typescript
// Using @nestjs/cache-manager with in-memory store
@Injectable()
export class MemoriesService {
  constructor(
    @Inject(CACHE_MANAGER) private cache: Cache,
    private memoriesRepo: MemoriesRepository,
  ) {}

  async getRelevant(deviceId: string, limit = 20): Promise<Memory[]> {
    const cacheKey = `memories:${deviceId}`;
    const cached = await this.cache.get<Memory[]>(cacheKey);
    if (cached) return cached;

    const memories = await this.memoriesRepo.findRelevant(deviceId, limit);
    await this.cache.set(cacheKey, memories, 120_000); // 2 min TTL
    return memories;
  }

  async invalidateCache(deviceId: string): Promise<void> {
    await this.cache.del(`memories:${deviceId}`);
  }
}
```

No Redis needed here — this is per-process, low-cardinality data. If the process restarts, the cache refills from PostgreSQL on the next request with negligible latency.

### ESP32 local TTS cache (MicroSD)

The backend includes cache hints in WebSocket responses so the ESP32 can cache audio locally. See [05-firmware.md](05-firmware.md) for the full MicroSD spec.

Two-tier cache flow:

```
Response sentence arrives:
  1. ESP32 checks /sdcard/cache/tts/<hash>.opus
  2. HIT  → play from SD card (0ms network latency)
  3. MISS → play from WebSocket stream, save to SD card in background

Result: first time = normal latency. Every subsequent time = instant.
```

### Updated WebSocket events for caching

New fields in existing events:

| Event | New fields | Purpose |
|-------|-----------|---------|
| response:chunk | `cacheKey?: string` | Hash for ESP32 to use as cache filename |
| response:end | `cacheKeys?: { hash: string, sentence: string }[]` | Full list of cache keys for this response |
| cache:invalidate | `keys: string[]` | Backend tells ESP32 to purge specific cached entries (e.g., voice/language changed) |
| cache:warmup | `keys: { hash: string, audio: Buffer }[]` | Optional: backend proactively sends common phrases to cache on idle |

### What NOT to cache

| Data | Why not |
|------|---------|
| STT results | Every utterance is unique audio |
| LLM responses | Every prompt is unique (different memories, history, transcript) |
| Conversation history (REST) | Low-frequency Flutter app access — PostgreSQL is fast enough |
| JWT tokens | Short-lived by design, validation is cheap |

---

## Rate limiting

| Scope | Limit | Storage | Purpose |
|-------|-------|---------|---------|
| Auth endpoints | 5 req/min per IP | Redis | Prevent brute force |
| REST API | 60 req/min per user | Redis | General abuse prevention |
| WebSocket audio | 10 conversations/min per device | Redis | Prevent AI cost runaway |

---

## Updated tech stack

| Component | Technology |
|-----------|-----------|
| Framework | NestJS |
| Database | PostgreSQL |
| Cache | Redis 7+ (TTS cache, sessions, rate limits) + @nestjs/cache-manager (in-memory) |
| ORM | TypeORM |
| WebSocket | @nestjs/websockets (Socket.IO or ws) |
| Auth | @nestjs/jwt, bcrypt, passport |
| Validation | class-validator, class-transformer |
| AI / LLM | @google/generative-ai (Gemini SDK — direct, no LangChain) |
| STT | @google-cloud/speech |
| TTS | @google-cloud/text-to-speech |
| Audio codec | @discordjs/opus or opusscript (Opus encode/decode) |
| Redis client | ioredis |

---

## Updated NestJS module structure

```
src/
  ai/
    interfaces/
      tokens.ts                  -- injection token symbols (incl. TTS_CACHE)
      stt-provider.interface.ts  -- ISttProvider + SttStream ports
      llm-provider.interface.ts  -- ILlmProvider port
      tts-provider.interface.ts  -- ITtsProvider port
      tts-cache.interface.ts     -- ITtsCache port
      audio-codec.interface.ts   -- IAudioCodec port
    adapters/
      google-stt.provider.ts     -- ISttProvider <- Google Cloud Speech (batch + streaming)
      gemini-llm.provider.ts     -- ILlmProvider <- Gemini SDK (batch + streaming)
      google-tts.provider.ts     -- ITtsProvider <- Google Cloud TTS
      redis-tts-cache.ts         -- ITtsCache <- Redis
      opus-audio.codec.ts        -- IAudioCodec  <- Opus via @discordjs/opus
    ai.module.ts                 -- binds ports to adapters
    ai.service.ts                -- streaming pipeline orchestrator (depends on ports only)
    prompt.service.ts            -- system prompt builder (internal logic)
    sentence-buffer.ts           -- LLM token stream -> sentence boundary detection
  cache/
    cache.module.ts              -- Redis client + TTS cache provider
  auth/
    auth.module.ts
    auth.controller.ts
    auth.service.ts
    jwt.strategy.ts
    device-token.guard.ts
  devices/
    devices.module.ts
    devices.controller.ts
    devices.service.ts
  conversations/
    conversations.module.ts
    conversations.controller.ts
    conversations.service.ts
  memories/
    memories.module.ts
    memories.controller.ts
    memories.service.ts
  scheduler/
    scheduler.module.ts            -- scheduler module
    scheduler.service.ts           -- per-device timer management
    reminder.service.ts            -- LLM-generated reminders with TTS caching
    pomodoro.service.ts            -- pomodoro state machine
    reminder.types.ts              -- types and configs
  gateway/
    audio.gateway.ts               -- WebSocket gateway (depends on AiService + SchedulerService)
    audio.gateway.module.ts
  database/
    entities/                      -- TypeORM entities
    migrations/
```

---

## Related docs

- [02-auth.md](02-auth.md) — Auth mechanisms and token flows
- [04-audio-pipeline.md](04-audio-pipeline.md) — WebSocket protocol and audio pipeline details
- [03-database.md](03-database.md) — Database schema
- [05-firmware.md](05-firmware.md) — MicroSD local TTS cache and resilience audio
