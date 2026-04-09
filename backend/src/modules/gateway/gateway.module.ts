import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  Conversation,
  Message,
  Device,
} from '../../core/database/entities';
import { AuthModule } from '../auth/auth.module';
import { AiModule } from '../ai/ai.module';
import { MemoriesModule } from '../memories/memories.module';
import { AudioGateway } from './audio.gateway';
import { SessionManager } from './session.manager';
import { ConversationPersistence } from './conversation.persistence';

@Module({
  imports: [
    TypeOrmModule.forFeature([Conversation, Message, Device]),
    AuthModule,
    AiModule,
    MemoriesModule,
  ],
  providers: [AudioGateway, SessionManager, ConversationPersistence],
  exports: [AudioGateway],
})
export class GatewayModule {}
