import { IsBoolean, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

export class UpdateSettingsDto {
  @IsString()
  @IsOptional()
  voice_preset?: string;

  @IsNumber()
  @Min(0.5)
  @Max(1.5)
  @IsOptional()
  voice_speed?: number;

  @IsNumber()
  @Min(0)
  @Max(1)
  @IsOptional()
  voice_stability?: number;

  @IsBoolean()
  @IsOptional()
  audio_wake_sound?: boolean;

  @IsBoolean()
  @IsOptional()
  audio_sleep_sound?: boolean;

  @IsBoolean()
  @IsOptional()
  audio_reminder_chime?: boolean;

  @IsNumber()
  @Min(0)
  @Max(1)
  @IsOptional()
  vad_sensitivity?: number;
  @IsNumber()
  @Min(0)
  @Max(100)
  @IsOptional()
  volume?: number;

  @IsNumber()
  @Min(0)
  @Max(100)
  @IsOptional()
  brightness?: number;

  @IsBoolean()
  @IsOptional()
  display_transcript?: boolean;

  @IsNumber()
  @IsOptional()
  idle_timeout_seconds?: number;

  @IsBoolean()
  @IsOptional()
  idle_chat_enabled?: boolean;

  @IsString()
  @IsOptional()
  idle_chat_frequency?: string;

  @IsString()
  @IsOptional()
  idle_animation_speed?: string;

  @IsString()
  @IsOptional()
  face_style?: string;

  @IsString()
  @IsOptional()
  idle_display_mode?: string;

  @IsNumber()
  @Min(100)
  @Max(500)
  @IsOptional()
  audio_jitter_ms?: number;

  @IsNumber()
  @Min(-90)
  @Max(-60)
  @IsOptional()
  presence_rssi_threshold?: number;

  @IsNumber()
  @Min(15)
  @Max(60)
  @IsOptional()
  presence_grace_period?: number;

  @IsNumber()
  @Min(2)
  @Max(10)
  @IsOptional()
  presence_silent_wake_minutes?: number;

  @IsBoolean()
  @IsOptional()
  presence_enabled?: boolean;

  @IsBoolean()
  @IsOptional()
  integrations_weather?: boolean;

  @IsString()
  @IsOptional()
  timezone?: string;

  @IsNumber()
  @Min(-90)
  @Max(90)
  @IsOptional()
  latitude?: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  @IsOptional()
  longitude?: number;
}
