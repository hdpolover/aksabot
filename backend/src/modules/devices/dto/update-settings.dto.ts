import { IsBoolean, IsNumber, IsOptional, Max, Min } from 'class-validator';

export class UpdateSettingsDto {
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
}
