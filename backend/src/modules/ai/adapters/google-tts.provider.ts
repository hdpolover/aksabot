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
        languageCode: options?.language ?? 'id-ID',
        name: options?.voice ?? undefined,
        ssmlGender: 'NEUTRAL' as const,
      },
      audioConfig: {
        audioEncoding: 'LINEAR16' as const,
        sampleRateHertz: 16000,
      },
    });

    return Buffer.from(response.audioContent as Uint8Array);
  }
}
