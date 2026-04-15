import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { ITtsProvider, TtsOptions } from '../interfaces';

// English voice presets — all male to match Aksa's identity.
// Ziggy is the default — energetic, slightly synthetic, fits the gen-z personality.
const VOICE_PRESETS_EN: Record<string, string> = {
  ziggy: '87n4zM8Wuy87vFILuKvE', // Ziggy — young, energetic, slightly synthetic (default)
  little_dude: 'fBD19tfE58bkETeiwUoC', // Little Dude
  sean: '4NJLA7OQNVkeKe4jVdHw', // Sean
  nelson: 'EaX6rnyDKjJx35tchi80', // Nelson
  nathan: 'g2W4HAjKvdW93AmsjsOx', // Nathan
};

// Indonesian voice presets
const VOICE_PRESETS_ID: Record<string, string> = {
  maskito: 'bEUyorX06jkv9l51DuwR', // Maskito (default)
  mark: 'DUnzBkwtjRWXPr6wRbmL', // Mark
  cornelius: '6sFKzaJr574YWVu4UuJF', // Cornelius
};

const DEFAULT_VOICE_EN = VOICE_PRESETS_EN.ziggy;
const DEFAULT_VOICE_ID_LANG = VOICE_PRESETS_ID.maskito;
const DEFAULT_SPEED = 0.9;
const DEFAULT_STABILITY = 0.35;

@Injectable()
export class ElevenLabsTtsProvider implements ITtsProvider {
  private readonly logger = new Logger(ElevenLabsTtsProvider.name);
  private readonly apiKey: string;

  constructor(private readonly config: ConfigService) {
    const apiKey = config.get<string>('ELEVENLABS_API_KEY');
    if (!apiKey) throw new Error('ELEVENLABS_API_KEY is required');
    this.apiKey = apiKey;
  }

  async synthesize(
    text: string,
    options?: TtsOptions,
    signal?: AbortSignal,
  ): Promise<Buffer> {
    // Resolve voice ID from preset name, using the language-appropriate map.
    const isId = options?.language === 'id';
    const presetMap = isId ? VOICE_PRESETS_ID : VOICE_PRESETS_EN;
    const defaultVoice = isId ? DEFAULT_VOICE_ID_LANG : DEFAULT_VOICE_EN;
    let voiceId = defaultVoice;
    if (options?.voice) {
      voiceId = presetMap[options.voice] ?? defaultVoice;
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
          model_id: 'eleven_multilingual_v2',
          voice_settings: {
            stability,
            similarity_boost: 0.8,
            style: 0,
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
