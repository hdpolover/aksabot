export interface TtsOptions {
  language?: string;
  voice?: string;
}

export interface ITtsProvider {
  synthesize(text: string, options?: TtsOptions): Promise<Buffer>;
}
