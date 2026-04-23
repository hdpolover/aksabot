import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MulterModule } from '@nestjs/platform-express';
import { FaceProfile } from '../../core/database/entities/face-profile.entity';
import { VisionInferenceService } from './vision-inference.service';
import { VisionService } from './vision.service';
import { VisionController } from './vision.controller';
import { VisionGatewayHandler } from './vision-gateway.handler';
import { GatewayModule } from '../gateway/gateway.module';
import { DevicesModule } from '../devices/devices.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([FaceProfile]),
    MulterModule.register({ storage: undefined }), // in-memory (buffer) storage
    forwardRef(() => GatewayModule),
    forwardRef(() => DevicesModule),
  ],
  controllers: [VisionController],
  providers: [VisionInferenceService, VisionService, VisionGatewayHandler],
  exports: [VisionService, VisionGatewayHandler],
})
export class VisionModule {}
