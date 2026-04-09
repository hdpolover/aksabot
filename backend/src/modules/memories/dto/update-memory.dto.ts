import { IsIn, IsOptional, IsString } from 'class-validator';

const CATEGORIES = [
  'personal',
  'preference',
  'work',
  'hobby',
  'relationship',
  'location',
  'routine',
  'other',
] as const;

export class UpdateMemoryDto {
  @IsString()
  @IsOptional()
  fact?: string;

  @IsString()
  @IsIn(CATEGORIES)
  @IsOptional()
  category?: string;
}
