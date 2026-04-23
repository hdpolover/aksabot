import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  Device,
  Conversation,
  Message,
  Memory,
  ResponsePool,
} from '../../core/database/entities';
import { GatewayModule } from '../gateway/gateway.module';
import { AiModule } from '../ai/ai.module';
import { DevicesService } from './devices.service';
import { DevicesController } from './devices.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Device,
      Conversation,
      Message,
      Memory,
      ResponsePool,
    ]),
    forwardRef(() => GatewayModule),
    AiModule,
  ],
  controllers: [DevicesController],
  providers: [DevicesService],
  exports: [DevicesService],
})
export class DevicesModule {}
