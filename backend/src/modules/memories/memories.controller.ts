import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { MemoriesService } from './memories.service';
import { UpdateMemoryDto } from './dto/update-memory.dto';

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

  @Put('memories/:id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateMemoryDto,
  ) {
    return this.memoriesService.update(id, dto);
  }

  @Delete('memories/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.memoriesService.remove(id);
  }
}
