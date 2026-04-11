export interface TtsOptions {
  language?: string;
  voice?: string;
  speed?: number;
  stability?: number;
}

export interface ITtsProvider {
  synthesize(text: string, options?: TtsOptions): Promise<Buffer>;
}
