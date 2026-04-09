export interface ITtsCache {
  /** Get cached TTS audio by key. Returns null if not cached. */
  get(key: string): Promise<Buffer | null>;

  /** Store TTS audio with key. TTL in seconds (default 7 days). */
  set(key: string, audio: Buffer, ttlSeconds?: number): Promise<void>;

  /** Delete a cached entry. */
  del(key: string): Promise<void>;

  /** Check if a key exists. */
  has(key: string): Promise<boolean>;
}
