import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { WsAdapter } from '@nestjs/platform-ws';
import { AppModule } from './app.module';
import { ResponseInterceptor } from './core/common/interceptors/response.interceptor';
import { GlobalExceptionFilter } from './core/common/filters/http-exception.filter';
import type { Request, Response, NextFunction } from 'express';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Log all HTTP requests
  const httpLogger = new Logger('HTTP');
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now();
    res.on('finish', () => {
      const ms = Date.now() - start;
      httpLogger.log(
        `${req.method} ${req.originalUrl} → ${res.statusCode} (${ms}ms)`,
      );
    });
    next();
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.useGlobalInterceptors(new ResponseInterceptor());
  app.useGlobalFilters(new GlobalExceptionFilter());
  app.useWebSocketAdapter(new WsAdapter(app));
  app.enableCors();

  const port = process.env.PORT ?? 4280;
  await app.listen(port);
  console.log(`Aksabot backend running on port ${port}`);
}
bootstrap();
