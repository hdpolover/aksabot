import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { AppConfigModule } from './core/config/config.module';
import { CacheModule } from './core/cache/cache.module';
import { DatabaseModule } from './core/database/database.module';
import { AuthModule } from './modules/auth/auth.module';
import { DevicesModule } from './modules/devices/devices.module';
import { AiModule } from './modules/ai/ai.module';
import { GatewayModule } from './modules/gateway/gateway.module';
import { ConversationsModule } from './modules/conversations/conversations.module';
import { MemoriesModule } from './modules/memories/memories.module';
import { SchedulerModule } from './modules/scheduler/scheduler.module';

@Module({
  imports: [
    AppConfigModule,
    ScheduleModule.forRoot(),
    CacheModule,
    DatabaseModule,
    AuthModule,
    DevicesModule,
    AiModule,
    GatewayModule,
    ConversationsModule,
    MemoriesModule,
    SchedulerModule,
  ],
})
export class AppModule {}
