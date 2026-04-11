import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { ITtsProvider, TtsOptions } from '../interfaces';

// Voice preset name → ElevenLabs voice ID mapping
const VOICE_PRESETS: Record<string, string> = {
  ziggy: '87n4zM8Wuy87vFILuKvE',  // Ziggy - Goofy Coyote (young, energetic boy)
  aria: '9BWtsMINqrJLrRacOk9x',   // Aria (warm female)
  roger: 'CwhRBWXzGAHq8TQ4Fs17',  // Roger (calm male)
  sarah: 'EXAVITQu4vr4xnSDxMaL',  // Sarah (friendly)
};

const DEFAULT_VOICE_ID = VOICE_PRESETS.ziggy;
const DEFAULT_SPEED = 0.7;
const DEFAULT_STABILITY = 0.6;

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
    // Resolve voice ID from preset name or direct ID
    let voiceId = DEFAULT_VOICE_ID;
    if (options?.voice) {
      voiceId = VOICE_PRESETS[options.voice] ?? options.voice;
    }

    const stability = options?.stability ?? DEFAULT_STABILITY;
    const speed = options?.speed ?? DEFAULT_SPEED;

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
          voice_settings: {
            stability,
            similarity_boost: 0.75,
            style: 0.3,
            use_speaker_boost: false,
          },
          speed,
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
