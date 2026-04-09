import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { MemoriesService } from './memories.service';

@Injectable()
export class MemoryDecayJob {
  private readonly logger = new Logger(MemoryDecayJob.name);

  constructor(private readonly memoriesService: MemoriesService) {}

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async handleDecay() {
    this.logger.log('Running memory decay job...');
    const result = await this.memoriesService.applyDecay();
    this.logger.log(
      `Decay complete: ${result.decayed} decayed, ${result.deleted} deleted`,
    );
  }
}
