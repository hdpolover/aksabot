import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Memory } from '../../core/database/entities';
import { MemoriesService } from './memories.service';
import { MemoriesController } from './memories.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Memory])],
  controllers: [MemoriesController],
  providers: [MemoriesService],
  exports: [MemoriesService],
})
export class MemoriesModule {}
