// eslint-disable-next-line @typescript-eslint/no-explicit-any
type OpusDecoderType = any;

/**
 * Decodes incoming Opus frames and plays them through the browser's speakers.
 * Also extracts amplitude for mouth animation.
 */
export class AudioPlayer {
  private audioCtx: AudioContext | null = null;
  private decoder: OpusDecoderType = null;
  private nextPlayTime = 0;
  private onAmplitude: (amp: number) => void;
  private onPlaybackEnd: (() => void) | null = null;
  private ready = false;
  private playing = false;
  private endCheckTimer: ReturnType<typeof setInterval> | null = null;

  constructor(onAmplitude: (amp: number) => void) {
    this.onAmplitude = onAmplitude;
  }

  async init(): Promise<void> {
    if (this.ready) return;

    this.audioCtx = new AudioContext({ sampleRate: 16000 });

    const { OpusDecoder } = await import('opus-decoder');
    this.decoder = new OpusDecoder({
      channels: 1,
      sampleRate: 16000,
    });
    await this.decoder.ready;

    this.ready = true;
  }

  /** Call when response:start arrives to reset playback timing */
  startPlayback(onEnd: () => void): void {
    this.playing = true;
    this.onPlaybackEnd = onEnd;
    if (this.audioCtx) {
      this.nextPlayTime = this.audioCtx.currentTime + 0.05;
    }
    // Start checking if playback has finished
    if (this.endCheckTimer) clearInterval(this.endCheckTimer);
  }

  /** Call when response:end arrives — backend is done sending, but audio may still be playing */
  markSendingDone(): void {
    // Start polling to detect when all scheduled audio has finished playing
    if (this.endCheckTimer) clearInterval(this.endCheckTimer);
    this.endCheckTimer = setInterval(() => {
      if (!this.audioCtx || !this.playing) {
        this.clearEndCheck();
        return;
      }
      // All audio has been played when currentTime passes the last scheduled frame
      if (this.audioCtx.currentTime >= this.nextPlayTime) {
        this.playing = false;
        this.onAmplitude(0);
        this.clearEndCheck();
        this.onPlaybackEnd?.();
        this.onPlaybackEnd = null;
      }
    }, 100);
  }

  private clearEndCheck(): void {
    if (this.endCheckTimer) {
      clearInterval(this.endCheckTimer);
      this.endCheckTimer = null;
    }
  }

  /** Returns true if audio is still being played through speakers */
  isPlaying(): boolean {
    return this.playing;
  }

  /** Feed a raw Opus frame (one WS binary message) */
  async feedOpusFrame(data: ArrayBuffer): Promise<void> {
    if (!this.ready || !this.decoder || !this.audioCtx) return;

    try {
      const result = await this.decoder.decodeFrame(new Uint8Array(data));

      if (!result.channelData || result.channelData.length === 0) return;

      const pcm: Float32Array = result.channelData[0];
      const samplesLength: number = result.samplesDecoded;

      // Compute RMS amplitude for mouth animation
      let sum = 0;
      for (let i = 0; i < samplesLength; i++) {
        sum += pcm[i] * pcm[i];
      }
      const rms = Math.sqrt(sum / samplesLength);
      this.onAmplitude(Math.min(1, rms * 8));

      // Schedule playback
      const buffer = this.audioCtx.createBuffer(1, samplesLength, 16000);
      buffer.copyToChannel(new Float32Array(pcm.buffer as ArrayBuffer, pcm.byteOffset, samplesLength), 0);

      const source = this.audioCtx.createBufferSource();
      source.buffer = buffer;
      source.connect(this.audioCtx.destination);

      const now = this.audioCtx.currentTime;
      if (this.nextPlayTime < now) {
        this.nextPlayTime = now + 0.01;
      }
      source.start(this.nextPlayTime);
      this.nextPlayTime += samplesLength / 16000;
    } catch {
      // Decode errors on individual frames are normal — skip
    }
  }

  /** Force stop (e.g. interruption) */
  stop(): void {
    this.playing = false;
    this.onAmplitude(0);
    this.clearEndCheck();
    this.onPlaybackEnd = null;
  }

  /** Resume AudioContext after user gesture (browser autoplay policy) */
  async resume(): Promise<void> {
    if (this.audioCtx?.state === 'suspended') {
      await this.audioCtx.resume();
    }
  }
}
