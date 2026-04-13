import { Inject, Injectable, Logger, Optional } from '@nestjs/common';
import { createHash } from 'crypto';
import {
  STT_PROVIDER,
  LLM_PROVIDER,
  TTS_PROVIDER,
  AUDIO_CODEC,
  TTS_CACHE,
} from './interfaces/tokens';
import type { ISttProvider, SttStream, SttOptions } from './interfaces';
import type { ILlmProvider } from './interfaces';
import type { ITtsProvider, TtsOptions } from './interfaces';
import type { ContextInfo, MoodHistoryEntry, WeatherData } from './prompt.service';
import type { IAudioCodec } from './interfaces';
import type { ITtsCache } from './interfaces/tts-cache.interface';
import { PromptService } from './prompt.service';
import type { MemoryEntry } from './prompt.service';
import { SentenceBuffer } from './sentence-buffer';

export interface CacheEntry {
  hash: string;
  sentence: string;
}

export type PipelineEvent =
  | { type: 'text'; text: string; emotion?: string; sfx?: string }
  | { type: 'audio'; data: Buffer; cacheKey?: string; emotion?: string; sfx?: string }
  | { type: 'done'; fullText: string; cacheKeys: CacheEntry[] };

// Known emotion tags → ESP32 expression mapping
const EMOTION_MAP: Record<string, string> = {
  happy: 'happy',
  sad: 'sad',
  excited: 'excited',
  calm: 'calm',
  confused: 'confused',
  focused: 'focused',
  sarcastic: 'sarcastic',
  sympathetic: 'sympathetic',
  neutral: 'neutral',
  // Common LLM variants
  playful: 'excited',
  annoyed: 'sarcastic',
  curious: 'confused',
  amused: 'happy',
  grateful: 'happy',
  concerned: 'sympathetic',
  confident: 'excited',
  thoughtful: 'focused',
  surprised: 'excited',
  warm: 'calm',
  teasing: 'sarcastic',
};

function extractEmotion(sentence: string): { text: string; emotion?: string; sfx?: string } {
  // Match [sfx:clipname] tags first (e.g. [sfx:rimshot])
  const sfxMatch = sentence.match(/\[\s*sfx:(\w+)\s*\]/i);
  const sfx = sfxMatch ? sfxMatch[1].toLowerCase() : undefined;

  // Match plain [emotion] tags — case-insensitive
  const allTags = [...sentence.matchAll(/\[\s*(\w+)\s*\]/gi)];
  let emotion: string | undefined;
  for (const m of allTags) {
    const tag = m[1].toLowerCase();
    if (tag in EMOTION_MAP) {
      emotion = EMOTION_MAP[tag];
      break;
    }
  }

  // Strip ALL bracket tags (emotion + sfx) and collapse extra whitespace
  const cleaned = sentence
    .replace(/\[\s*sfx:\w+\s*\]/gi, '')
    .replace(/\[\s*\w+\s*\]/g, '')
    .replace(/\s{2,}/g, ' ')
    .trim();
  return { text: cleaned, emotion, sfx };
}

// Per-emotion TTS voice adjustments (speed + stability modulation)
const EMOTION_VOICE_MODS: Record<string, { speedMul: number; stabilityMul: number }> = {
  excited:     { speedMul: 1.15, stabilityMul: 0.7 },   // Faster, more expressive
  happy:       { speedMul: 1.05, stabilityMul: 0.8 },   // Slightly faster, lively
  sarcastic:   { speedMul: 0.95, stabilityMul: 0.6 },   // Slightly slower, very variable
  calm:        { speedMul: 0.90, stabilityMul: 1.0 },   // Slower, stable
  sympathetic: { speedMul: 0.90, stabilityMul: 0.9 },   // Slower, gentle
  sad:         { speedMul: 0.85, stabilityMul: 0.9 },   // Slowest, subdued
  focused:     { speedMul: 1.00, stabilityMul: 1.0 },   // Normal, precise
  confused:    { speedMul: 0.95, stabilityMul: 0.7 },   // Slightly slower, uncertain
  neutral:     { speedMul: 1.00, stabilityMul: 1.0 },   // No change
};

function applyEmotionToVoice(base: TtsOptions | undefined, emotion?: string): TtsOptions {
  const opts: TtsOptions = { ...base };
  if (!emotion) return opts;
  const mod = EMOTION_VOICE_MODS[emotion];
  if (!mod) return opts;
  opts.speed = (opts.speed ?? 0.7) * mod.speedMul;
  opts.stability = (opts.stability ?? 0.6) * mod.stabilityMul;
  // Clamp to ElevenLabs ranges
  if (opts.speed! < 0.5) opts.speed = 0.5;
  if (opts.speed! > 1.5) opts.speed = 1.5;
  if (opts.stability! < 0.0) opts.stability = 0.0;
  if (opts.stability! > 1.0) opts.stability = 1.0;
  return opts;
}

@Injectable()
export class AiService {
  private readonly logger = new Logger(AiService.name);

  constructor(
    @Inject(STT_PROVIDER) private readonly stt: ISttProvider,
    @Inject(LLM_PROVIDER) private readonly llm: ILlmProvider,
    @Inject(TTS_PROVIDER) private readonly tts: ITtsProvider,
    @Inject(AUDIO_CODEC) private readonly codec: IAudioCodec,
    @Optional() @Inject(TTS_CACHE) private readonly ttsCache: ITtsCache | null,
    private readonly prompt: PromptService,
  ) {}

  createSttStream(options?: SttOptions): SttStream {
    return this.stt.createStream(options);
  }

  async refreshWeather(lat: number, lon: number): Promise<void> {
    return this.prompt.refreshWeather(lat, lon);
  }

  getWeatherData(): WeatherData | null {
    return this.prompt.getWeatherData();
  }

  getDetectedTimezone(): string | null {
    return this.prompt.getDetectedTimezone();
  }

  formatTimeForDevice(timezone?: string): { time: string; date: string } {
    return this.prompt.formatTimeForDevice(timezone);
  }

  decodeAudio(opusChunk: Buffer): Buffer {
    return this.codec.decode(opusChunk);
  }

  encodeAudio(pcmChunk: Buffer): Buffer {
    return this.codec.encode(pcmChunk);
  }

  /**
   * Generate a cache key for a TTS sentence.
   * Hash of text + voice settings ensures uniqueness per voice config.
   */
  ttsCacheKey(text: string, options?: TtsOptions): string {
    const input = `${text}|${options?.language ?? 'auto'}|${options?.voice ?? ''}|${options?.speed ?? ''}|${options?.stability ?? ''}`;
    return createHash('sha256').update(input).digest('hex').slice(0, 16);
  }

  /**
   * Synthesize TTS with Redis cache. Returns Opus-encoded audio.
   */
  async synthesizeWithCache(
    sentence: string,
    language?: string,
    voiceOptions?: TtsOptions,
    signal?: AbortSignal,
  ): Promise<{ opusAudio: Buffer; pcmAudio: Buffer; cacheKey: string }> {
    // Only override language if explicitly provided — don't clobber voiceOptions.language with undefined
    const ttsOpts: TtsOptions = { ...voiceOptions, ...(language !== undefined ? { language } : {}) };
    const cacheKey = this.ttsCacheKey(sentence, ttsOpts);

    // Check cache (cache hits are instant, signal not needed)
    if (this.ttsCache) {
      const cached = await this.ttsCache.get(cacheKey);
      if (cached) {
        this.logger.debug(`TTS cache hit: ${cacheKey}`);
        return { opusAudio: cached, pcmAudio: Buffer.alloc(0), cacheKey };
      }
    }

    // Synthesize and encode — pass signal so fetch can be aborted mid-response
    const pcmAudio = await this.tts.synthesize(sentence, ttsOpts, signal);
    const opusAudio = this.codec.encode(pcmAudio);

    // Store in cache (non-blocking)
    if (this.ttsCache) {
      this.ttsCache.set(cacheKey, opusAudio).catch((err) =>
        this.logger.warn(`TTS cache store failed: ${err.message}`),
      );
    }

    return { opusAudio, pcmAudio, cacheKey };
  }

  /**
   * Process a finalized transcript into a streamed audio response.
   * Yields events as they become available:
   *   - { type: 'text', text } — a completed sentence
   *   - { type: 'audio', data, cacheKey } — Opus audio for that sentence
   *   - { type: 'done', fullText, cacheKeys } — pipeline complete with cache manifest
   */
  async *processTranscript(
    transcript: string,
    memories: MemoryEntry[],
    history: { role: string; content: string }[],
    voiceOptions?: TtsOptions,
    context?: ContextInfo,
    moodHistory?: MoodHistoryEntry[],
    signal?: AbortSignal,
  ): AsyncGenerator<PipelineEvent> {
    const systemPrompt = this.prompt.buildSystemPrompt(memories, context, moodHistory);
    const messages = this.prompt.buildMessages(history, transcript);

    const sentenceBuffer = new SentenceBuffer();
    const llmStream = this.llm.generateStream(systemPrompt, messages);
    let fullResponseText = '';
    const cacheKeys: CacheEntry[] = [];

    for await (const token of llmStream) {
      // Stop consuming LLM tokens if the pipeline was cancelled — saves Gemini spend
      if (signal?.aborted) return;

      fullResponseText += token;

      const rawSentence = sentenceBuffer.feed(token);
      if (rawSentence) {
        if (signal?.aborted) return;
        const { text: cleanText, emotion, sfx } = extractEmotion(rawSentence);
        const emotionVoice = applyEmotionToVoice(voiceOptions, emotion);
        // synthesizeWithCache passes signal to fetch — aborts the HTTP request if cancelled
        const { opusAudio, cacheKey } = await this.synthesizeWithCache(
          cleanText,
          undefined,
          emotionVoice,
          signal,
        );
        cacheKeys.push({ hash: cacheKey, sentence: cleanText });

        yield { type: 'text', text: cleanText, emotion, sfx };
        yield { type: 'audio', data: opusAudio, cacheKey, emotion, sfx };
      }
    }

    if (signal?.aborted) return;

    const remaining = sentenceBuffer.flush();
    if (remaining) {
      const { text: cleanText, emotion, sfx } = extractEmotion(remaining);
      const emotionVoice = applyEmotionToVoice(voiceOptions, emotion);
      const { opusAudio, cacheKey } = await this.synthesizeWithCache(
        cleanText,
        undefined,
        emotionVoice,
        signal,
      );
      cacheKeys.push({ hash: cacheKey, sentence: cleanText });

      yield { type: 'text', text: cleanText, emotion, sfx };
      yield { type: 'audio', data: opusAudio, cacheKey, emotion, sfx };
    }

    yield { type: 'done', fullText: fullResponseText, cacheKeys };
  }
}
