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
import type { ITtsProvider } from './interfaces';
import type { IAudioCodec } from './interfaces';
import type { ITtsCache } from './interfaces/tts-cache.interface';
import { PromptService } from './prompt.service';
import type { PersonalityConfig, MemoryEntry } from './prompt.service';
import { SentenceBuffer } from './sentence-buffer';

export interface CacheEntry {
  hash: string;
  sentence: string;
}

export type PipelineEvent =
  | { type: 'text'; text: string }
  | { type: 'audio'; data: Buffer; cacheKey?: string }
  | { type: 'done'; fullText: string; cacheKeys: CacheEntry[] };

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

  decodeAudio(opusChunk: Buffer): Buffer {
    return this.codec.decode(opusChunk);
  }

  encodeAudio(pcmChunk: Buffer): Buffer {
    return this.codec.encode(pcmChunk);
  }

  /**
   * Generate a cache key for a TTS sentence.
   * Hash of text + language ensures uniqueness.
   */
  ttsCacheKey(text: string, language?: string): string {
    const input = `${text}|${language ?? 'auto'}`;
    return createHash('sha256').update(input).digest('hex').slice(0, 16);
  }

  /**
   * Synthesize TTS with Redis cache. Returns Opus-encoded audio.
   */
  private async synthesizeWithCache(
    sentence: string,
    language?: string,
  ): Promise<{ opusAudio: Buffer; cacheKey: string }> {
    const cacheKey = this.ttsCacheKey(sentence, language);

    // Check cache
    if (this.ttsCache) {
      const cached = await this.ttsCache.get(cacheKey);
      if (cached) {
        this.logger.debug(`TTS cache hit: ${cacheKey}`);
        return { opusAudio: cached, cacheKey };
      }
    }

    // Synthesize and encode
    const pcmAudio = await this.tts.synthesize(sentence, { language });
    const opusAudio = this.codec.encode(pcmAudio);

    // Store in cache (non-blocking)
    if (this.ttsCache) {
      this.ttsCache.set(cacheKey, opusAudio).catch((err) =>
        this.logger.warn(`TTS cache store failed: ${err.message}`),
      );
    }

    return { opusAudio, cacheKey };
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
    personality: PersonalityConfig,
    memories: MemoryEntry[],
    history: { role: string; content: string }[],
  ): AsyncGenerator<PipelineEvent> {
    const systemPrompt = this.prompt.buildSystemPrompt(personality, memories);
    const messages = this.prompt.buildMessages(history, transcript);

    const sentenceBuffer = new SentenceBuffer();
    const llmStream = this.llm.generateStream(systemPrompt, messages);
    let fullResponseText = '';
    const cacheKeys: CacheEntry[] = [];

    for await (const token of llmStream) {
      fullResponseText += token;

      const sentence = sentenceBuffer.feed(token);
      if (sentence) {
        const { opusAudio, cacheKey } = await this.synthesizeWithCache(
          sentence,
          personality.language,
        );
        cacheKeys.push({ hash: cacheKey, sentence });

        yield { type: 'text', text: sentence };
        yield { type: 'audio', data: opusAudio, cacheKey };
      }
    }

    const remaining = sentenceBuffer.flush();
    if (remaining) {
      const { opusAudio, cacheKey } = await this.synthesizeWithCache(
        remaining,
        personality.language,
      );
      cacheKeys.push({ hash: cacheKey, sentence: remaining });

      yield { type: 'text', text: remaining };
      yield { type: 'audio', data: opusAudio, cacheKey };
    }

    yield { type: 'done', fullText: fullResponseText, cacheKeys };
  }
}
