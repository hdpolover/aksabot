import { IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

export class VoicePreviewDto {
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
}
