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

    return Buffer.from(response.audioContent as Uint8Array);
  }
}
