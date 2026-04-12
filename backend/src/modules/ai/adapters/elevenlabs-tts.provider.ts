import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { ITtsProvider, TtsOptions } from '../interfaces';

// Voice preset name → ElevenLabs voice ID mapping
// All presets are male to match Aksa's identity.
// Ziggy is the default — energetic, slightly synthetic, fits the gen-z personality.
const VOICE_PRESETS: Record<string, string> = {
  ziggy:       '87n4zM8Wuy87vFILuKvE',  // Ziggy — young, energetic, slightly synthetic (default)
  little_dude: 'fBD19tfE58bkETeiwUoC',  // Little Dude
  sean:        '4NJLA7OQNVkeKe4jVdHw',  // Sean
  nelson:      'EaX6rnyDKjJx35tchi80',  // Nelson
  nathan:      'g2W4HAjKvdW93AmsjsOx',  // Nathan
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

  async synthesize(text: string, options?: TtsOptions, signal?: AbortSignal): Promise<Buffer> {
    // Resolve voice ID from preset name or direct ID
    let voiceId = DEFAULT_VOICE_ID;
    if (options?.voice) {
      voiceId = VOICE_PRESETS[options.voice] ?? options.voice;
    }

    const stability = options?.stability ?? DEFAULT_STABILITY;
    const speed = options?.speed ?? DEFAULT_SPEED;

    const outputFormat = options?.outputFormat ?? 'pcm_16000';

    const res = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=${outputFormat}`,
      {
        method: 'POST',
        signal,
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
