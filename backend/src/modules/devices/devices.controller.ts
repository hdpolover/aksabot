import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../../core/common/decorators/current-user.decorator';
import type { RequestUser } from '../../core/common/decorators/current-user.decorator';
import { DevicesService } from './devices.service';
import { CreateDeviceDto } from './dto/create-device.dto';
import { UpdateSettingsDto } from './dto/update-settings.dto';
import { UpdatePersonalityDto } from './dto/update-personality.dto';

@Controller('devices')
@UseGuards(JwtAuthGuard)
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Post()
  create(@CurrentUser() user: RequestUser, @Body() dto: CreateDeviceDto) {
    return this.devicesService.create(user.userId, dto);
  }

  @Get()
  findAll(@CurrentUser() user: RequestUser) {
    return this.devicesService.findAllByUser(user.userId);
  }

  @Get(':id')
  findOne(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.findById(id, user.userId);
  }

  @Patch(':id/settings')
  updateSettings(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Body() dto: UpdateSettingsDto,
  ) {
    return this.devicesService.updateSettings(id, user.userId, dto);
  }

  @Get(':id/personality')
  getPersonality(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.getPersonality(id, user.userId);
  }

  @Patch(':id/personality')
  updatePersonality(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
    @Body() dto: UpdatePersonalityDto,
  ) {
    return this.devicesService.updatePersonality(id, user.userId, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.devicesService.remove(id, user.userId);
  }
}
