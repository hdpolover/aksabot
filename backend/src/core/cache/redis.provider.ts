import { Provider } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

export const REDIS_CLIENT = Symbol('REDIS_CLIENT');

export const redisProvider: Provider = {
  provide: REDIS_CLIENT,
  inject: [ConfigService],
  useFactory: (config: ConfigService) => {
    const host = config.get<string>('REDIS_HOST', 'localhost');
    const port = config.get<number>('REDIS_PORT', 6312);

    const client = new Redis({ host, port, lazyConnect: true });

    client.on('connect', () => {
      console.log(`[Redis] Connected to ${host}:${port}`);
    });

    client.on('error', (err) => {
      console.error(`[Redis] Error: ${err.message}`);
    });

    client.connect().catch(() => {
      // Will retry automatically
    });

    return client;
  },
};
