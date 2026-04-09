import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { SchedulerService } from './scheduler.service';
import { PomodoroService } from './pomodoro.service';
import type { ReminderConfig } from './types';

@Controller('devices/:deviceId')
@UseGuards(JwtAuthGuard)
export class SchedulerController {
  constructor(
    private readonly scheduler: SchedulerService,
    private readonly pomodoro: PomodoroService,
  ) {}

  // ── Reminders config ──────────────────────────────────

  @Get('reminders')
  getReminderConfig(@Param('deviceId', ParseUUIDPipe) deviceId: string) {
    return this.scheduler.getReminderConfig(deviceId);
  }

  @Put('reminders')
  updateReminderConfig(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
    @Body() config: Partial<ReminderConfig>,
  ) {
    return this.scheduler.updateReminderConfig(deviceId, config);
  }

  // ── Pomodoro ──────────────────────────────────────────

  @Post('pomodoro/start')
  startPomodoro(@Param('deviceId', ParseUUIDPipe) deviceId: string) {
    return this.pomodoro.start(deviceId);
  }

  @Post('pomodoro/stop')
  @HttpCode(HttpStatus.NO_CONTENT)
  stopPomodoro(@Param('deviceId', ParseUUIDPipe) deviceId: string) {
    this.pomodoro.stop(deviceId);
  }

  @Get('pomodoro')
  getPomodoroStatus(@Param('deviceId', ParseUUIDPipe) deviceId: string) {
    return this.pomodoro.getInfo(deviceId);
  }

  // ── Focus mode ────────────────────────────────────────

  @Post('focus')
  startFocusMode(
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
    @Body() body: { durationMinutes?: number },
  ) {
    const duration = body.durationMinutes ?? 60;
    this.scheduler.startFocusMode(deviceId, duration);
    return { active: true, durationMinutes: duration };
  }

  @Delete('focus')
  @HttpCode(HttpStatus.NO_CONTENT)
  stopFocusMode(@Param('deviceId', ParseUUIDPipe) deviceId: string) {
    this.scheduler.clearFocusMode(deviceId);
  }
}
