import { Inject, Injectable, Logger } from '@nestjs/common';
import { TTS_PROVIDER, AUDIO_CODEC, TTS_CACHE } from '../ai/interfaces/tokens';
import type { ITtsProvider } from '../ai/interfaces';
import type { IAudioCodec } from '../ai/interfaces';
import type { ITtsCache } from '../ai/interfaces/tts-cache.interface';
import { AiService } from '../ai/ai.service';
import { ResponsePoolService } from './response-pool.service';
import {
  REMINDER_DISPLAY,
  type ReminderPayload,
  type ReminderType,
  type PomodoroState,
} from './types';

@Injectable()
export class ReminderService {
  private readonly logger = new Logger(ReminderService.name);

  constructor(
    private readonly responsePool: ResponsePoolService,
    private readonly aiService: AiService,
    @Inject(TTS_PROVIDER) private readonly tts: ITtsProvider,
    @Inject(TTS_CACHE) private readonly ttsCache: ITtsCache,
    @Inject(AUDIO_CODEC) private readonly codec: IAudioCodec,
  ) {}

  /**
   * Generate a reminder payload from the response pool.
   * Uses cached TTS when available, synthesizes on miss.
   */
  async generate(
    deviceId: string,
    type: ReminderType,
  ): Promise<ReminderPayload> {
    const response = await this.responsePool.pickLru(deviceId, type);

    const { audio, cacheKey } = await this.getOrSynthesizeAudio(
      response.text,
      response.ttsCacheKey,
    );

    // Update cache key if it was newly generated
    if (!response.ttsCacheKey && cacheKey) {
      this.responsePool
        .updateCacheKey(response.id, cacheKey)
        .catch((err) =>
          this.logger.warn(`Failed to update cache key: ${err.message}`),
        );
    }

    return {
      type,
      text: response.text,
      audio,
      cacheKey,
      display: REMINDER_DISPLAY[type],
    };
  }

  /**
   * Generate a pomodoro transition reminder.
   */
  async generatePomodoro(
    deviceId: string,
    state: PomodoroState,
  ): Promise<ReminderPayload> {
    const category =
      state.phase === 'focus' ? 'pomodoro_focus' : 'pomodoro_break';
    const response = await this.responsePool.pickLru(deviceId, category);

    const { audio, cacheKey } = await this.getOrSynthesizeAudio(
      response.text,
      response.ttsCacheKey,
    );

    if (!response.ttsCacheKey && cacheKey) {
      this.responsePool.updateCacheKey(response.id, cacheKey).catch(() => {});
    }

    const display =
      state.phase === 'focus'
        ? { expression: 'focused', screenMode: 'reminder' as const, durationMs: 8_000 }
        : { expression: 'encouraging', screenMode: 'reminder' as const, durationMs: 8_000 };

    return {
      type: category,
      text: response.text,
      audio,
      cacheKey,
      display,
    };
  }

  private async getOrSynthesizeAudio(
    text: string,
    existingCacheKey: string | null,
  ): Promise<{ audio: Buffer; cacheKey: string }> {
    // Try existing cache key
    if (existingCacheKey) {
      const cached = await this.ttsCache.get(existingCacheKey);
      if (cached) {
        return { audio: cached, cacheKey: existingCacheKey };
      }
    }

    // Synthesize
    const cacheKey = this.aiService.ttsCacheKey(text);
    const cachedByHash = await this.ttsCache.get(cacheKey);
    if (cachedByHash) {
      return { audio: cachedByHash, cacheKey };
    }

    const pcm = await this.tts.synthesize(text, {});
    const audio = this.codec.encode(pcm);

    // Store non-blocking
    this.ttsCache.set(cacheKey, audio).catch(() => {});

    return { audio, cacheKey };
  }
}
