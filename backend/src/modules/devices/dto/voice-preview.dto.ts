import { IsIn, IsNumber, IsOptional, IsString, MaxLength, Min, Max } from 'class-validator';

export class VoicePreviewDto {
  @IsIn(['en', 'id'])
  @IsOptional()
  language?: 'en' | 'id';

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

  @IsString()
  @MaxLength(300)
  @IsOptional()
  text?: string;
}
