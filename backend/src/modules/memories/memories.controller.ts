import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { MemoriesService } from './memories.service';

@Controller()
@UseGuards(JwtAuthGuard)
export class MemoriesController {
  constructor(private readonly memoriesService: MemoriesService) {}

  @Get('devices/:deviceId/memories')
  findByDevice(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
    @Query('category') category?: string,
  ) {
    return this.memoriesService.findByDevice(deviceId, category);
  }

  @Delete('memories/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.memoriesService.remove(id);
  }
}
