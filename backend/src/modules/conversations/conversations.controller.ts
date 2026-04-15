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
import { CurrentUser } from '../../core/common/decorators/current-user.decorator';
import type { RequestUser } from '../../core/common/decorators/current-user.decorator';
import { ConversationsService } from './conversations.service';

@Controller()
@UseGuards(JwtAuthGuard)
export class ConversationsController {
  constructor(private readonly conversationsService: ConversationsService) {}

  @Get('devices/:deviceId/conversations')
  findByDevice(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
    @CurrentUser() user: RequestUser,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('q') q?: string,
  ) {
    return this.conversationsService.findByDevice(
      deviceId,
      user.userId,
      page ? parseInt(page) : 1,
      limit ? parseInt(limit) : 20,
      q?.trim() || undefined,
    );
  }

  @Delete('conversations/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  delete(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.conversationsService.delete(id, user.userId);
  }

  @Get('conversations/:id/messages')
  findMessages(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.conversationsService.findMessages(
      id,
      user.userId,
      page ? parseInt(page) : 1,
      limit ? parseInt(limit) : 50,
    );
  }
}
