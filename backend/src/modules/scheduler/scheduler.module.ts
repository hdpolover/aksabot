import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Device, ResponsePool } from '../../core/database/entities';
import { AiModule } from '../ai/ai.module';
import { MemoriesModule } from '../memories/memories.module';
import { GatewayModule } from '../gateway/gateway.module';
import { ResponsePoolService } from './response-pool.service';
import { ReminderService } from './reminder.service';
import { PomodoroService } from './pomodoro.service';
import { ProactiveService } from './proactive.service';
import { SchedulerService } from './scheduler.service';
import { SchedulerController } from './scheduler.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([ResponsePool, Device]),
    AiModule,
    MemoriesModule,
    forwardRef(() => GatewayModule),
  ],
  controllers: [SchedulerController],
  providers: [
    ResponsePoolService,
    ReminderService,
    PomodoroService,
    ProactiveService,
    SchedulerService,
  ],
  exports: [SchedulerService, PomodoroService, ProactiveService],
})
export class SchedulerModule {}
