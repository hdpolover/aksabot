import { Injectable } from '@nestjs/common';
import OpusScript from 'opusscript';
import type { IAudioCodec } from '../interfaces';

const FRAME_SAMPLES = 320; // 20ms at 16kHz
const FRAME_BYTES = FRAME_SAMPLES * 2; // 640 bytes (16-bit mono)

@Injectable()
export class OpusAudioCodec implements IAudioCodec {
  private encoder: OpusScript;

  constructor() {
    this.encoder = new OpusScript(16000, 1, OpusScript.Application.AUDIO);
    this.encoder.setBitrate(64000);
  }

  /**
   * Encode PCM buffer to Opus.
   * Input can be a single frame (640 bytes) or a full TTS output (many frames).
   * Output: concatenated Opus frames with 2-byte big-endian length prefix each.
   * Format: [len16][opus_frame][len16][opus_frame]...
   */
  encode(pcm: Buffer): Buffer {
    const totalFrames = Math.floor(pcm.length / FRAME_BYTES);
    const chunks: Buffer[] = [];

    for (let i = 0; i < totalFrames; i++) {
      const frameStart = i * FRAME_BYTES;
      const framePcm = pcm.subarray(frameStart, frameStart + FRAME_BYTES);
      const opusFrame = Buffer.from(
        this.encoder.encode(Buffer.from(framePcm), FRAME_SAMPLES),
      );

      // 2-byte big-endian length prefix
      const header = Buffer.alloc(2);
      header.writeUInt16BE(opusFrame.length);
      chunks.push(header, opusFrame);
    }

    return Buffer.concat(chunks);
  }

  /**
   * Decode a single Opus frame to PCM.
   * Used by the gateway when receiving audio from ESP32.
   */
  decode(encoded: Buffer): Buffer {
    return Buffer.from(this.encoder.decode(encoded));
  }
}
