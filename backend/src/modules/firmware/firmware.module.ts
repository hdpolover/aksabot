import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FirmwareRelease } from '../../core/database/entities';
import { DevicesModule } from '../devices/devices.module';
import { GatewayModule } from '../gateway/gateway.module';
import { FirmwareService } from './firmware.service';
import { FirmwareController } from './firmware.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([FirmwareRelease]),
    DevicesModule,
    forwardRef(() => GatewayModule),
  ],
  controllers: [FirmwareController],
  providers: [FirmwareService],
  exports: [FirmwareService],
})
export class FirmwareModule {}
