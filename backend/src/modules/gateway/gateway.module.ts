import { Module, forwardRef } from '@nestjs/common';
import { FirmwareModule } from '../firmware/firmware.module';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  Conversation,
  Message,
  Device,
} from '../../core/database/entities';
import { AuthModule } from '../auth/auth.module';
import { AiModule } from '../ai/ai.module';
import { MemoriesModule } from '../memories/memories.module';
import { SchedulerModule } from '../scheduler/scheduler.module';
import { AudioGateway } from './audio.gateway';
import { SessionManager } from './session.manager';
import { ConversationPersistence } from './conversation.persistence';
import { VoiceCommandService } from './voice-command.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([Conversation, Message, Device]),
    AuthModule,
    AiModule,
    MemoriesModule,
    forwardRef(() => SchedulerModule),
    forwardRef(() => FirmwareModule),
  ],
  providers: [AudioGateway, SessionManager, ConversationPersistence, VoiceCommandService],
  exports: [AudioGateway, SessionManager],
})
export class GatewayModule {}
