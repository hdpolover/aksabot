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
}
