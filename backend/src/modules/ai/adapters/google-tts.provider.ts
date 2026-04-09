import { Injectable } from '@nestjs/common';
import { TextToSpeechClient } from '@google-cloud/text-to-speech';
import type { ITtsProvider, TtsOptions } from '../interfaces';

@Injectable()
export class GoogleTtsProvider implements ITtsProvider {
  private client: TextToSpeechClient;

  constructor() {
    this.client = new TextToSpeechClient();
  }

  async synthesize(text: string, options?: TtsOptions): Promise<Buffer> {
    const [response] = await this.client.synthesizeSpeech({
      input: { text },
      voice: {
        languageCode: options?.language ?? 'en-US',
        name: options?.voice ?? 'en-US-Neural2-A',
        ssmlGender: 'MALE' as const,
      },
      audioConfig: {
        audioEncoding: 'LINEAR16' as const,
        sampleRateHertz: 16000,
        pitch: 3.0,          // slightly higher — gives a compact, robotic quality
        speakingRate: 1.1,   // slightly fast — crisp, bot-like cadence
      },
    });

    const pcm = Buffer.from(response.audioContent as Uint8Array);

    // Apply subtle ring modulation for metallic/robotic overtone
    return applyRingMod(pcm, 200, 0.15);
  }
}

/**
 * Ring modulation: multiply audio signal by a sine carrier wave.
 * Creates a metallic, robotic overtone when mixed subtly with the dry signal.
 *
 * @param pcm    16-bit signed LE PCM buffer
 * @param freqHz Carrier frequency (150-300 Hz for robotic effect)
 * @param mix    Wet/dry mix (0.0 = original, 1.0 = full ring mod)
 */
function applyRingMod(
  pcm: Buffer,
  freqHz: number,
  mix: number,
): Buffer {
  const sampleRate = 16000;
  const numSamples = pcm.length / 2;
  const output = Buffer.alloc(pcm.length);

  for (let i = 0; i < numSamples; i++) {
    const sample = pcm.readInt16LE(i * 2);
    const carrier = Math.sin(2 * Math.PI * freqHz * (i / sampleRate));
    const modulated = sample * carrier;

    // Mix dry + wet
    const mixed = sample * (1 - mix) + modulated * mix;

    // Clamp to int16 range
    const clamped = Math.max(-32768, Math.min(32767, Math.round(mixed)));
    output.writeInt16LE(clamped, i * 2);
  }

  return output;
}
