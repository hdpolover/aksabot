export interface IAudioCodec {
  encode(pcm: Buffer): Buffer;
  decode(encoded: Buffer): Buffer;
}
