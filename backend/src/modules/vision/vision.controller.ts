import {
  Controller,
  Post,
  Get,
  Delete,
  Param,
  Query,
  Body,
  Request,
  UploadedFile,
  UploadedFiles,
  UseGuards,
  UseInterceptors,
  HttpCode,
  HttpStatus,
  ParseUUIDPipe,
  BadRequestException,
} from '@nestjs/common';
import { FilesInterceptor, FileInterceptor } from '@nestjs/platform-express';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { VisionService } from './vision.service';
import { AudioGateway } from '../gateway/audio.gateway';
import { EnrollFaceDto } from './dto/enroll-face.dto';

@Controller('vision')
@UseGuards(JwtAuthGuard)
export class VisionController {
  constructor(
    private readonly visionService: VisionService,
    private readonly gateway: AudioGateway,
  ) {}

  /** Upload one or more JPEG photos to enroll a person. */
  @Post('enroll')
  @UseInterceptors(FilesInterceptor('photos', 10))
  async enroll(
    @Request() req: any,
    @UploadedFiles() files: Express.Multer.File[],
    @Body() dto: EnrollFaceDto,
  ) {
    if (!files || files.length === 0) throw new BadRequestException('No photos uploaded');
    const buffers = files.map(f => f.buffer);
    return this.visionService.enroll(req.user.id, dto.name, buffers);
  }

  /** Trigger ESP32-CAM to capture 8 enrollment frames, then enroll automatically. */
  @Post('enroll/capture')
  async captureEnroll(
    @Request() req: any,
    @Query('deviceId', ParseUUIDPipe) cameraDeviceId: string,
    @Body() dto: EnrollFaceDto,
  ) {
    this.gateway.setPendingEnrollment(cameraDeviceId, req.user.id, dto.name);
    this.gateway.sendVisionCapture(cameraDeviceId);
    return { ok: true, message: 'Capture triggered — awaiting frames from camera' };
  }

  /** Upload a photo and get back who it matches (or unknown). */
  @Post('recognize')
  @UseInterceptors(FileInterceptor('photo'))
  async recognize(
    @Request() req: any,
    @UploadedFile() file: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('No photo uploaded');
    const embedding = await this.visionService.detectAndEmbed(file.buffer);
    if (!embedding) return { detected: false, name: null, confidence: 0, unknown: true };
    const result = await this.visionService.findBestMatch(req.user.id, embedding);
    return { detected: true, ...result };
  }

  @Get('profiles')
  getProfiles(@Request() req: any) {
    return this.visionService.getProfiles(req.user.id);
  }

  @Delete('profiles/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  deleteProfile(@Request() req: any, @Param('id', ParseUUIDPipe) id: string) {
    return this.visionService.deleteProfile(req.user.id, id);
  }
}
