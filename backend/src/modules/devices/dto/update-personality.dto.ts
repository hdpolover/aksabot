import { IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdatePersonalityDto {
  @IsString()
  @IsOptional()
  @MaxLength(50)
  name?: string;

  @IsString()
  @IsOptional()
  @MaxLength(200)
  tone?: string;

  @IsString()
  @IsOptional()
  @MaxLength(10)
  language?: string;

  @IsString()
  @IsOptional()
  @MaxLength(2000)
  system_prompt?: string;
}
