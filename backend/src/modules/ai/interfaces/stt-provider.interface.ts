import { EventEmitter } from 'events';

export interface SttOptions {
  sampleRate?: number;
  languages?: string[];
}

export interface SttResult {
  transcript: string;
  confidence: number;
  language?: string;
}

export interface SttStream extends EventEmitter {
  write(pcmChunk: Buffer): void;
  end(): void;
  destroy(): void;
}

export interface ISttProvider {
  transcribe(pcmAudio: Buffer, options?: SttOptions): Promise<SttResult>;
  createStream(options?: SttOptions): SttStream;
}
