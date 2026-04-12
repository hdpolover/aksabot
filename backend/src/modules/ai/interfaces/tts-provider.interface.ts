export interface TtsOptions {
  language?: string;
  voice?: string;
  speed?: number;
  stability?: number;
  /** ElevenLabs output format. Defaults to 'pcm_16000' for ESP32.
   *  Use 'mp3_44100_128' for app-side preview playback. */
  outputFormat?: string;
}

export interface ITtsProvider {
  synthesize(text: string, options?: TtsOptions, signal?: AbortSignal): Promise<Buffer>;
}
