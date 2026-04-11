/**
 * Captures microphone audio, resamples to 16kHz mono 16-bit PCM,
 * and sends frames via a callback.
 */
export class AudioRecorder {
  private audioCtx: AudioContext | null = null;
  private stream: MediaStream | null = null;
  private sourceNode: MediaStreamAudioSourceNode | null = null;
  private processorNode: ScriptProcessorNode | null = null;
  private onFrame: (pcm: ArrayBuffer) => void;
  private recording = false;

  constructor(onFrame: (pcm: ArrayBuffer) => void) {
    this.onFrame = onFrame;
  }

  async start(): Promise<void> {
    if (this.recording) return;

    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: 16000,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });

    // Use the actual sample rate the browser gives us
    this.audioCtx = new AudioContext({ sampleRate: 16000 });

    // If browser doesn't support 16kHz, we get whatever it gives and resample
    const actualRate = this.audioCtx.sampleRate;

    this.sourceNode = this.audioCtx.createMediaStreamSource(this.stream);

    // ScriptProcessorNode: deprecated but universally supported
    // Buffer size of 4096 at 16kHz = 256ms chunks
    // At 48kHz (common browser default) = ~85ms chunks
    const bufferSize = 4096;
    this.processorNode = this.audioCtx.createScriptProcessor(bufferSize, 1, 1);

    this.processorNode.onaudioprocess = (event) => {
      if (!this.recording) return;

      const input = event.inputBuffer.getChannelData(0); // Float32, mono

      // Resample if needed
      let samples: Float32Array;
      if (actualRate !== 16000) {
        const ratio = 16000 / actualRate;
        const newLen = Math.round(input.length * ratio);
        samples = new Float32Array(newLen);
        for (let i = 0; i < newLen; i++) {
          const srcIdx = i / ratio;
          const lo = Math.floor(srcIdx);
          const hi = Math.min(lo + 1, input.length - 1);
          const frac = srcIdx - lo;
          samples[i] = input[lo] * (1 - frac) + input[hi] * frac;
        }
      } else {
        samples = input;
      }

      // Convert Float32 [-1,1] to Int16 PCM
      const pcm = new Int16Array(samples.length);
      for (let i = 0; i < samples.length; i++) {
        const s = Math.max(-1, Math.min(1, samples[i]));
        pcm[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
      }

      this.onFrame(pcm.buffer);
    };

    this.sourceNode.connect(this.processorNode);
    this.processorNode.connect(this.audioCtx.destination); // Required for processing to work
    this.recording = true;
  }

  stop(): void {
    this.recording = false;
    this.processorNode?.disconnect();
    this.sourceNode?.disconnect();
    this.stream?.getTracks().forEach((t) => t.stop());
    this.audioCtx?.close();
    this.processorNode = null;
    this.sourceNode = null;
    this.stream = null;
    this.audioCtx = null;
  }
}
