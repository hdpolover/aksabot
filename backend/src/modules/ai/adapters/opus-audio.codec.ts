import { Injectable } from '@nestjs/common';
import { OpusEncoder } from '@discordjs/opus';
import type { IAudioCodec } from '../interfaces';

@Injectable()
export class OpusAudioCodec implements IAudioCodec {
  private encoder: OpusEncoder;

  constructor() {
    // 16kHz sample rate, 1 channel (mono)
    this.encoder = new OpusEncoder(16000, 1);
  }

  encode(pcm: Buffer): Buffer {
    return this.encoder.encode(pcm);
  }

  decode(encoded: Buffer): Buffer {
    return this.encoder.decode(encoded);
  }
}
