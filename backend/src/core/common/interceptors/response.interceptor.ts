import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

/**
 * Wraps REST responses in a consistent { data, meta? } envelope.
 * If the response already has a `data` key (e.g., paginated responses),
 * it passes through unchanged.
 */
@Injectable()
export class ResponseInterceptor implements NestInterceptor {
  intercept(_context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      map((response) => {
        if (response === undefined || response === null) return response;
        if (response.data !== undefined) return response;
        return { data: response };
      }),
    );
  }
}
