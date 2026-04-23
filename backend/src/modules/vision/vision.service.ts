import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { FaceProfile } from '../../core/database/entities/face-profile.entity';
import { VisionInferenceService } from './vision-inference.service';

export interface IdentityResult {
  name: string | null;
  confidence: number;
  unknown: boolean;
}

/** Distance threshold for cosine similarity — below this = confident match. */
const MATCH_THRESHOLD = 0.4;

@Injectable()
export class VisionService {
  private readonly logger = new Logger(VisionService.name);

  constructor(
    private readonly inference: VisionInferenceService,
    @InjectRepository(FaceProfile)
    private readonly profileRepo: Repository<FaceProfile>,
    private readonly dataSource: DataSource,
  ) {}

  /**
   * Enroll a person by running inference on one or more JPEG frames.
   * If multiple frames given, uses the one with the highest detection score.
   * Saves the resulting embedding as a face profile.
   */
  async enroll(userId: string, name: string, jpegBuffers: Buffer[]): Promise<FaceProfile> {
    let bestEmbedding: number[] | null = null;
    let bestScore = -1;

    for (const buf of jpegBuffers) {
      const detection = await this.inference.detect(buf);
      if (!detection) continue;
      if (detection.score > bestScore) {
        const embedding = await this.inference.embed(buf, detection.box);
        if (embedding) {
          bestEmbedding = embedding;
          bestScore = detection.score;
        }
      }
    }

    if (!bestEmbedding) {
      throw new Error('No face detected in any of the provided frames');
    }

    const profile = this.profileRepo.create({ userId, name, embedding: bestEmbedding });
    const saved = await this.profileRepo.save(profile);
    this.logger.log(`Enrolled face for user ${userId}: ${name} (id=${saved.id})`);
    return saved;
  }

  /**
   * Find the best matching profile for a given embedding using pgvector cosine similarity.
   * Returns unknown=true if no profiles exist or distance exceeds MATCH_THRESHOLD.
   */
  async findBestMatch(userId: string, embedding: number[]): Promise<IdentityResult> {
    const vectorLiteral = `[${embedding.join(',')}]`;
    const rows = await this.dataSource.query<{ id: string; name: string; distance: string }[]>(
      `SELECT id, name, (embedding::vector <=> $1::float8[]::vector) AS distance
       FROM face_profiles
       WHERE user_id = $2
       ORDER BY distance
       LIMIT 1`,
      [vectorLiteral, userId],
    );

    if (rows.length === 0) {
      return { name: null, confidence: 0, unknown: true };
    }

    const distance = parseFloat(rows[0].distance);
    const confidence = Math.max(0, 1 - distance / MATCH_THRESHOLD);

    if (distance >= MATCH_THRESHOLD) {
      return { name: null, confidence, unknown: true };
    }

    return { name: rows[0].name, confidence, unknown: false };
  }

  async getProfiles(userId: string): Promise<FaceProfile[]> {
    return this.profileRepo.find({ where: { userId }, order: { createdAt: 'ASC' } });
  }

  async deleteProfile(userId: string, profileId: string): Promise<void> {
    const profile = await this.profileRepo.findOne({ where: { id: profileId, userId } });
    if (!profile) throw new NotFoundException('Face profile not found');
    await this.profileRepo.delete(profileId);
  }

  /** Detect face and compute embedding from a single JPEG buffer. Returns null if no face found. */
  async detectAndEmbed(jpegBuffer: Buffer): Promise<number[] | null> {
    const detection = await this.inference.detect(jpegBuffer);
    if (!detection) return null;
    return this.inference.embed(jpegBuffer, detection.box);
  }
}
