import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { ITtsProvider, TtsOptions } from '../interfaces';

const DEFAULT_VOICE_ID = '87n4zM8Wuy87vFILuKvE'; // Ziggy - Goofy Coyote (young, energetic boy)

const DEFAULT_VOICE_SETTINGS = {
  stability: 0.6,
  similarity_boost: 0.75,
  style: 0.3,
  use_speaker_boost: false,
};

const DEFAULT_SPEED = 0.8;

@Injectable()
export class ElevenLabsTtsProvider implements ITtsProvider {
  private readonly logger = new Logger(ElevenLabsTtsProvider.name);
  private readonly apiKey: string;

  constructor(private readonly config: ConfigService) {
    const apiKey = config.get<string>('ELEVENLABS_API_KEY');
    if (!apiKey) throw new Error('ELEVENLABS_API_KEY is required');
    this.apiKey = apiKey;
  }

  async synthesize(text: string, options?: TtsOptions): Promise<Buffer> {
    const voiceId = options?.voice ?? DEFAULT_VOICE_ID;

    const res = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=pcm_16000`,
      {
        method: 'POST',
        headers: {
          'xi-api-key': this.apiKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          text,
          model_id: 'eleven_turbo_v2_5',
          voice_settings: DEFAULT_VOICE_SETTINGS,
          speed: DEFAULT_SPEED,
        }),
      },
    );

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`ElevenLabs TTS failed (${res.status}): ${body}`);
    }

    const pcm = Buffer.from(await res.arrayBuffer());
    this.logger.debug(
      `Synthesized "${text.slice(0, 40)}..." → ${pcm.length} bytes PCM`,
    );
    return pcm;
  }
}
