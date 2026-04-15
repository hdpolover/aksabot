import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigService } from '@nestjs/config';
import {
  User,
  Device,
  Conversation,
  Message,
  Memory,
  ResponsePool,
  MoodEntry,
  FirmwareRelease,
} from './entities';
// Migrations imported for migrationsRun (disabled — using synchronize for now)
// import { Init1775743820807 } from './migrations/1775743820807-Init';

@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        host: config.get('DB_HOST', 'localhost'),
        port: config.get<number>('DB_PORT', 5432),
        username: config.get('DB_USER', 'aksabot'),
        password: config.get('DB_PASSWORD'),
        database: config.get('DB_NAME', 'aksabot'),
        entities: [
          User,
          Device,
          Conversation,
          Message,
          Memory,
          ResponsePool,
          MoodEntry,
          FirmwareRelease,
        ],
        synchronize: true,
      }),
    }),
  ],
})
export class DatabaseModule {}
