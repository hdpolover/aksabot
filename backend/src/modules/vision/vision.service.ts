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

// Threshold for aligned ArcFace embeddings.
// Same-person (aligned): ~0.05-0.20. Different person: ~0.45-0.90.
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
   * Enroll a person: detect + embed each frame, average all embeddings,
   * re-normalise, and save. Also stores a 48×48 thumbnail from the first valid frame.
   */
  async enroll(userId: string, name: string, jpegBuffers: Buffer[]): Promise<FaceProfile> {
    const embeddings: number[][] = [];
    let thumbnailBuf: Buffer | null = null;

    for (const buf of jpegBuffers) {
      const detection = await this.inference.detect(buf);
      if (!detection) continue;
      const embedding = await this.inference.embed(buf, detection);
      if (!embedding) continue;
      embeddings.push(embedding);
      if (!thumbnailBuf) {
        thumbnailBuf = await this.inference.thumbnail(buf, detection);
      }
    }

    if (embeddings.length === 0) {
      throw new Error('No face detected in any of the provided frames');
    }

    // Average all embeddings then re-L2-normalise
    const dim = embeddings[0].length;
    const mean = new Array<number>(dim).fill(0);
    for (const emb of embeddings) for (let i = 0; i < dim; i++) mean[i] += emb[i];
    for (let i = 0; i < dim; i++) mean[i] /= embeddings.length;
    const norm = Math.sqrt(mean.reduce((s, v) => s + v * v, 0));
    const averaged = norm > 0 ? mean.map(v => v / norm) : mean;

    const thumbnailUrl = thumbnailBuf
      ? 'data:image/jpeg;base64,' + thumbnailBuf.toString('base64')
      : null;

    this.logger.log(`Enrolled ${name}: averaged ${embeddings.length}/${jpegBuffers.length} frames`);
    const profile = this.profileRepo.create({ userId, name, embedding: averaged, thumbnailUrl });
    const saved = await this.profileRepo.save(profile);
    this.logger.log(`Enrolled face for user ${userId}: ${name} (id=${saved.id})`);
    return saved;
  }

  /**
   * Detect ALL faces in the image, embed each, and return the best match
   * across all faces × all enrolled profiles. Handles multi-person photos.
   */
  async recognizeAll(userId: string, jpegBuffer: Buffer): Promise<IdentityResult & { detected: boolean }> {
    const faces = await this.inference.detectAll(jpegBuffer);
    if (faces.length === 0) return { detected: false, name: null, confidence: 0, unknown: true };

    let bestMatch: (IdentityResult & { detected: true }) | null = null;

    for (const face of faces) {
      const embedding = await this.inference.embed(jpegBuffer, face);
      if (!embedding) continue;
      const result = await this.findBestMatch(userId, embedding);
      if (!result.unknown) {
        if (!bestMatch || result.confidence > bestMatch.confidence) {
          bestMatch = { detected: true, ...result };
        }
      }
    }

    if (bestMatch) return bestMatch;
    // No face matched — return unknown with best confidence seen
    return { detected: true, name: null, confidence: 0, unknown: true };
  }

  /**
   * Find the best matching profile for a single embedding via pgvector cosine similarity.
   */
  async findBestMatch(userId: string, embedding: number[]): Promise<IdentityResult> {
    const vectorLiteral = `[${embedding.join(',')}]`;
    const rows = await this.dataSource.query<{ id: string; name: string; distance: string }[]>(
      `SELECT id, name, (embedding::vector <=> '${vectorLiteral}'::vector) AS distance
       FROM face_profiles
       WHERE user_id = $1
       ORDER BY distance
       LIMIT 1`,
      [userId],
    );

    if (rows.length === 0) return { name: null, confidence: 0, unknown: true };

    const distance = parseFloat(rows[0].distance);
    this.logger.debug(`Match "${rows[0].name}": d=${distance.toFixed(4)} threshold=${MATCH_THRESHOLD}`);
    const confidence = Math.max(0, 1 - Math.pow(distance / MATCH_THRESHOLD, 2));

    return distance >= MATCH_THRESHOLD
      ? { name: null, confidence, unknown: true }
      : { name: rows[0].name, confidence, unknown: false };
  }

  async getProfiles(userId: string): Promise<FaceProfile[]> {
    return this.profileRepo.find({ where: { userId }, order: { createdAt: 'ASC' } });
  }

  async deleteProfile(userId: string, profileId: string): Promise<void> {
    const profile = await this.profileRepo.findOne({ where: { id: profileId, userId } });
    if (!profile) throw new NotFoundException('Face profile not found');
    await this.profileRepo.delete(profileId);
  }

  /** Used by VisionGatewayHandler for the live ESP32-CAM stream. */
  async detectAndEmbed(jpegBuffer: Buffer): Promise<number[] | null> {
    const detection = await this.inference.detect(jpegBuffer);
    if (!detection) return null;
    return this.inference.embed(jpegBuffer, detection);
  }
}
