import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type Redis from 'ioredis';
import { REDIS_CLIENT } from '../../cache/cache.module';

export const RATE_LIMIT_KEY = 'rateLimit';

export interface RateLimitOptions {
  /** Max requests in the window */
  limit: number;
  /** Window size in seconds */
  windowSeconds: number;
  /** Key prefix — 'ip' uses client IP, 'user' uses JWT user ID */
  keyType: 'ip' | 'user';
}

/**
 * Decorator to apply rate limiting to a controller or handler.
 */
export const RateLimit = (options: RateLimitOptions) =>
  SetMetadata(RATE_LIMIT_KEY, options);

@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const options = this.reflector.getAllAndOverride<RateLimitOptions>(
      RATE_LIMIT_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!options) return true; // No rate limit configured

    const request = context.switchToHttp().getRequest();
    const key = this.buildKey(request, options);

    const current = await this.redis.incr(key);
    if (current === 1) {
      await this.redis.expire(key, options.windowSeconds);
    }

    if (current > options.limit) {
      const ttl = await this.redis.ttl(key);
      throw new HttpException(
        {
          statusCode: HttpStatus.TOO_MANY_REQUESTS,
          message: 'Too many requests',
          retryAfter: ttl,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    return true;
  }

  private buildKey(request: any, options: RateLimitOptions): string {
    const prefix = 'rl:';
    if (options.keyType === 'user' && request.user?.userId) {
      return `${prefix}user:${request.user.userId}`;
    }
    const ip =
      request.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
      request.ip ||
      request.connection?.remoteAddress ||
      'unknown';
    return `${prefix}ip:${ip}`;
  }
}
