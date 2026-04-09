import { Inject, Injectable } from '@nestjs/common';
import type Redis from 'ioredis';
import { REDIS_CLIENT } from '../../../core/cache/cache.module';
import type { ITtsCache } from '../interfaces/tts-cache.interface';

const PREFIX = 'tts:';
const DEFAULT_TTL = 7 * 24 * 60 * 60; // 7 days

@Injectable()
export class RedisTtsCache implements ITtsCache {
  constructor(@Inject(REDIS_CLIENT) private readonly redis: Redis) {}

  async get(key: string): Promise<Buffer | null> {
    const data = await this.redis.getBuffer(PREFIX + key);
    return data ?? null;
  }

  async set(
    key: string,
    audio: Buffer,
    ttlSeconds = DEFAULT_TTL,
  ): Promise<void> {
    await this.redis.set(PREFIX + key, audio, 'EX', ttlSeconds);
  }

  async del(key: string): Promise<void> {
    await this.redis.del(PREFIX + key);
  }

  async has(key: string): Promise<boolean> {
    return (await this.redis.exists(PREFIX + key)) === 1;
  }
}
