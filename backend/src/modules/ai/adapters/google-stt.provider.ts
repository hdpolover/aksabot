import { Injectable } from '@nestjs/common';
import { SpeechClient } from '@google-cloud/speech';
import { EventEmitter } from 'events';
import type {
  ISttProvider,
  SttStream,
  SttResult,
  SttOptions,
} from '../interfaces';

class GoogleSttStream extends EventEmitter implements SttStream {
  private recognizeStream: ReturnType<SpeechClient['streamingRecognize']>;
  private finalEmitted = false;
  private bytesWritten = 0;

  constructor(client: SpeechClient, config: Record<string, any>) {
    super();
    this.recognizeStream = client.streamingRecognize({
      config,
      interimResults: true,
    });

    this.recognizeStream.on('data', (response: any) => {
      const result = response.results?.[0];
      if (!result) return;

      const transcript = result.alternatives?.[0]?.transcript ?? '';

      if (result.isFinal) {
        this.finalEmitted = true;
        this.emit('final', {
          transcript,
          confidence: result.alternatives?.[0]?.confidence ?? 0,
          language: result.languageCode,
        } satisfies SttResult);
      } else {
        this.emit('partial', transcript);
      }
    });

    this.recognizeStream.on('error', (err: Error) => {
      this.emit('error', err);
    });

    // When Google STT closes the stream without emitting a final result
    // (e.g., all audio was silence, or audio was too short), we emit a
    // 'final' with an empty transcript so the pipeline can send a proper
    // error to the device instead of hanging silently.
    this.recognizeStream.on('end', () => {
      if (!this.finalEmitted) {
        this.emit('final', {
          transcript: '',
          confidence: 0,
        } satisfies SttResult);
      }
    });
  }

  write(pcmChunk: Buffer): void {
    if (this.recognizeStream.destroyed) return;
    this.bytesWritten += pcmChunk.length;
    this.recognizeStream.write(pcmChunk);
  }

  end(): void {
    this.recognizeStream.end();
  }

  destroy(): void {
    this.recognizeStream.destroy();
  }
}

@Injectable()
export class GoogleSttProvider implements ISttProvider {
  private client: SpeechClient;

  constructor() {
    this.client = new SpeechClient();
  }

  async transcribe(pcmAudio: Buffer, options?: SttOptions): Promise<SttResult> {
    const [response] = await this.client.recognize({
      audio: { content: pcmAudio.toString('base64') },
      config: this.buildConfig(options),
    });

    const best = response.results?.[0]?.alternatives?.[0];
    return {
      transcript:
        response.results
          ?.map((r) => r.alternatives?.[0]?.transcript)
          .join(' ') ?? '',
      confidence: best?.confidence ?? 0,
      language: response.results?.[0]?.languageCode ?? undefined,
    };
  }

  createStream(options?: SttOptions): SttStream {
    return new GoogleSttStream(this.client, this.buildConfig(options));
  }

  private buildConfig(options?: SttOptions) {
    return {
      encoding: 'LINEAR16' as const,
      sampleRateHertz: options?.sampleRate ?? 16000,
      languageCode: options?.languages?.[0] ?? 'en-US',
      alternativeLanguageCodes: options?.languages?.slice(1) ?? ['id-ID'],
    };
  }
}
