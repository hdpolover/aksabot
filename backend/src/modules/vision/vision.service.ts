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

// Threshold tuned for aligned ArcFace embeddings (5-point face alignment applied).
// Aligned same-person: typically 0.05-0.20. Different person: typically 0.45-0.90.
// 0.28 gives comfortable margin between the two distributions.
const MATCH_THRESHOLD = 0.28;

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
    const embeddings: number[][] = [];

    for (const buf of jpegBuffers) {
      const detection = await this.inference.detect(buf);
      if (!detection) continue;
      const embedding = await this.inference.embed(buf, detection);
      if (embedding) embeddings.push(embedding);
    }

    if (embeddings.length === 0) {
      throw new Error('No face detected in any of the provided frames');
    }

    // Average all embeddings then re-L2-normalise → more robust than single-best
    const dim = embeddings[0].length;
    const mean = new Array<number>(dim).fill(0);
    for (const emb of embeddings) {
      for (let i = 0; i < dim; i++) mean[i] += emb[i];
    }
    for (let i = 0; i < dim; i++) mean[i] /= embeddings.length;
    const norm = Math.sqrt(mean.reduce((s, v) => s + v * v, 0));
    const averaged = norm > 0 ? mean.map(v => v / norm) : mean;

    this.logger.log(`Enrolled ${name}: averaged ${embeddings.length}/${jpegBuffers.length} frames`);

    const profile = this.profileRepo.create({ userId, name, embedding: averaged });
    const saved = await this.profileRepo.save(profile);
    this.logger.log(`Enrolled face for user ${userId}: ${name} (id=${saved.id})`);
    return saved;
  }

  /**
   * Find the best matching profile for a given embedding using pgvector cosine similarity.
   * Returns unknown=true if no profiles exist or distance exceeds MATCH_THRESHOLD.
   */
  async findBestMatch(userId: string, embedding: number[]): Promise<IdentityResult> {
    // Embed vector literal directly in SQL — values come from our ONNX model, not user input.
    // pgvector accepts '[...]' notation; parameterizing it as $1::float8[] fails because
    // PostgreSQL text→float8[] casting expects '{...}' not '[...]'.
    const vectorLiteral = `[${embedding.join(',')}]`;
    const rows = await this.dataSource.query<{ id: string; name: string; distance: string }[]>(
      `SELECT id, name, (embedding::vector <=> '${vectorLiteral}'::vector) AS distance
       FROM face_profiles
       WHERE user_id = $1
       ORDER BY distance
       LIMIT 1`,
      [userId],
    );

    if (rows.length === 0) {
      return { name: null, confidence: 0, unknown: true };
    }

    const distance = parseFloat(rows[0].distance);
    this.logger.debug(`Distance to "${rows[0].name}": ${distance.toFixed(4)} (threshold=${MATCH_THRESHOLD})`);
    const confidence = Math.max(0, 1 - Math.pow(distance / MATCH_THRESHOLD, 2));

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
    return this.inference.embed(jpegBuffer, detection);
  }
}
