import { Module } from '@nestjs/common';
import {
  STT_PROVIDER,
  LLM_PROVIDER,
  TTS_PROVIDER,
  AUDIO_CODEC,
} from './interfaces/tokens';
import { GoogleSttProvider } from './adapters/google-stt.provider';
import { GeminiLlmProvider } from './adapters/gemini-llm.provider';
import { GoogleTtsProvider } from './adapters/google-tts.provider';
import { OpusAudioCodec } from './adapters/opus-audio.codec';
import { PromptService } from './prompt.service';
import { AiService } from './ai.service';

@Module({
  providers: [
    { provide: STT_PROVIDER, useClass: GoogleSttProvider },
    { provide: LLM_PROVIDER, useClass: GeminiLlmProvider },
    { provide: TTS_PROVIDER, useClass: GoogleTtsProvider },
    { provide: AUDIO_CODEC, useClass: OpusAudioCodec },
    PromptService,
    AiService,
  ],
  exports: [AiService],
})
export class AiModule {}
