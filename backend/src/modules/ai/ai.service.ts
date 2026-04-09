import { Inject, Injectable } from '@nestjs/common';
import {
  STT_PROVIDER,
  LLM_PROVIDER,
  TTS_PROVIDER,
  AUDIO_CODEC,
} from './interfaces/tokens';
import type { ISttProvider, SttStream, SttOptions } from './interfaces';
import type { ILlmProvider } from './interfaces';
import type { ITtsProvider } from './interfaces';
import type { IAudioCodec } from './interfaces';
import { PromptService } from './prompt.service';
import type { PersonalityConfig, MemoryEntry } from './prompt.service';
import { SentenceBuffer } from './sentence-buffer';

export type PipelineEvent =
  | { type: 'text'; text: string }
  | { type: 'audio'; data: Buffer }
  | { type: 'done'; fullText: string };

@Injectable()
export class AiService {
  constructor(
    @Inject(STT_PROVIDER) private readonly stt: ISttProvider,
    @Inject(LLM_PROVIDER) private readonly llm: ILlmProvider,
    @Inject(TTS_PROVIDER) private readonly tts: ITtsProvider,
    @Inject(AUDIO_CODEC) private readonly codec: IAudioCodec,
    private readonly prompt: PromptService,
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
   * Encode PCM to Opus (used for sending audio back to ESP32).
   */
  encodeAudio(pcmChunk: Buffer): Buffer {
    return this.codec.encode(pcmChunk);
  }

  /**
   * Process a finalized transcript into a streamed audio response.
   * Yields events as they become available:
   *   - { type: 'text', text } — a completed sentence
   *   - { type: 'audio', data } — Opus audio for that sentence
   *   - { type: 'done', fullText } — pipeline complete
   *
   * The caller (gateway) can abort by breaking out of the generator.
   */
  async *processTranscript(
    transcript: string,
    personality: PersonalityConfig,
    memories: MemoryEntry[],
    history: { role: string; content: string }[],
  ): AsyncGenerator<PipelineEvent> {
    // 1. Build prompt with memories
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
        const pcmAudio = await this.tts.synthesize(sentence, {
          language: personality.language,
        });
        const opusAudio = this.codec.encode(pcmAudio);

        yield { type: 'text', text: sentence };
        yield { type: 'audio', data: opusAudio };
      }
    }

    // 3. Flush remaining text in sentence buffer
    const remaining = sentenceBuffer.flush();
    if (remaining) {
      const pcmAudio = await this.tts.synthesize(remaining, {
        language: personality.language,
      });
      const opusAudio = this.codec.encode(pcmAudio);

      yield { type: 'text', text: remaining };
      yield { type: 'audio', data: opusAudio };
    }

    yield { type: 'done', fullText: fullResponseText };
  }
}
