import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Conversation, Memory, Message } from '../../core/database/entities';
import { AiModule } from '../ai/ai.module';
import { MemoriesService } from './memories.service';
import { MemoryExtractorService } from './memory-extractor.service';
import { MemoryDecayJob } from './memory-decay.job';
import { MemoriesController } from './memories.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Conversation, Memory, Message]), AiModule],
  controllers: [MemoriesController],
  providers: [MemoriesService, MemoryExtractorService, MemoryDecayJob],
  exports: [MemoriesService],
})
export class MemoriesModule {}
