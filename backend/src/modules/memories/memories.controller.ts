import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Logger,
  Param,
  ParseUUIDPipe,
  Post,
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
  private readonly logger = new Logger(MemoriesController.name);
  constructor(private readonly memoriesService: MemoriesService) {}

  @Post('devices/:deviceId/memories/extract')
  async extractFromConversation(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
    @Body('conversationId') conversationId: string,
  ) {
    this.logger.log(`Manual extraction for device ${deviceId}, conversation ${conversationId}`);
    const memories = await this.memoriesService.extractFromConversation(
      conversationId,
      deviceId,
    );
    return { extracted: memories.length, memories };
  }

  /**
   * Diagnostic: extract memories from the most recent conversation that has messages.
   * Hit this to test extraction without needing to know a conversation ID.
   */
  @Post('devices/:deviceId/memories/extract-latest')
  async extractFromLatest(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
  ) {
    const result = await this.memoriesService.extractFromLatestConversation(deviceId);
    return result;
  }

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
