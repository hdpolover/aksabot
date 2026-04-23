import { IsString, Length } from 'class-validator';

export class EnrollFaceDto {
  @IsString()
  @Length(1, 100)
  name: string;
}
