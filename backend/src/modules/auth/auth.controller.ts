import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { AuthService } from './auth.service';
import { RegisterDto, LoginDto, RefreshDto } from './dto';
import {
  RateLimit,
  RateLimitGuard,
} from '../../core/common/guards/rate-limit.guard';

@Controller('auth')
@UseGuards(RateLimitGuard)
@RateLimit({ limit: 5, windowSeconds: 60, keyType: 'ip' })
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.authService.refresh(dto.refreshToken);
  }
}
