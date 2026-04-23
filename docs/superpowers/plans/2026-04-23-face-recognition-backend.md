# Face Recognition — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a vision module to the NestJS backend that receives JPEG frames from ESP32-CAM via WebSocket, runs buffalo_l ONNX inference to detect and embed faces, matches against enrolled face profiles in PostgreSQL using pgvector, and pushes identified person context to the paired aksabot device session.

**Architecture:** ESP32-CAM connects via WebSocket with a device token, sends `vision:frame` binary JPEG messages at 1fps. Backend detects face (SCRFD-10G), embeds (ArcFace R50), cosine-searches pgvector. Match result pushed as `face:identity` to paired aksabot device. Enrolled profiles stored in `face_profiles` table with `float8[]` embedding column.

**Tech Stack:** NestJS 11, TypeORM (`synchronize: true`), PostgreSQL + pgvector extension, `onnxruntime-node`, `sharp` (image processing), InsightFace buffalo_l ONNX models (det_10g.onnx + w600k_r50.onnx).

---

## File Structure

```
backend/
  models/
    buffalo_l/
      det_10g.onnx          ← download separately (not committed)
      w600k_r50.onnx        ← download separately (not committed)
      .gitkeep
  src/
    core/database/
      entities/
        face-profile.entity.ts    ← CREATE new
        index.ts                  ← MODIFY: export FaceProfile
      database.module.ts          ← MODIFY: add FaceProfile entity + pgvector init
    modules/
      vision/
        dto/
          enroll-face.dto.ts      ← CREATE new
        vision-inference.service.ts  ← CREATE new (buffalo_l ONNX)
        vision.service.ts            ← CREATE new (enrollment + recognition)
        vision.controller.ts         ← CREATE new (REST API)
        vision-gateway.handler.ts    ← CREATE new (WS vision:frame handler)
        vision.module.ts             ← CREATE new
        vision-inference.service.spec.ts  ← CREATE new
        vision.service.spec.ts            ← CREATE new
        vision.controller.spec.ts         ← CREATE new
      gateway/
        session.manager.ts    ← MODIFY: add currentIdentity to DeviceSession
        audio.gateway.ts      ← MODIFY: inject VisionGatewayHandler, add vision events, context injection
        gateway.module.ts     ← MODIFY: import VisionModule
    app.module.ts             ← MODIFY: import VisionModule
```

---

## Task 1: Install Dependencies + Model Setup

**Files:**
- Modify: `backend/package.json` (via npm install)
- Create: `backend/models/buffalo_l/.gitkeep`
- Modify: `backend/.gitignore` (ignore model files)

- [ ] **Step 1: Install npm packages**

```bash
cd backend
npm install onnxruntime-node sharp
npm install --save-dev @types/sharp
```

Expected: packages install without errors.

- [ ] **Step 2: Create model directory**

```bash
mkdir -p backend/models/buffalo_l
touch backend/models/buffalo_l/.gitkeep
```

- [ ] **Step 3: Add to .gitignore**

Add to `backend/.gitignore`:
```
# ONNX models (too large for git — download separately)
models/buffalo_l/*.onnx
```

- [ ] **Step 4: Download buffalo_l models**

Download from InsightFace model zoo. These are the two files needed:
```bash
# From https://github.com/deepinsight/insightface/releases or their model zoo
# Place in backend/models/buffalo_l/
# det_10g.onnx  (~16MB)  — SCRFD-10GF face detector
# w600k_r50.onnx (~166MB) — ArcFace R50 face recognizer
```

Verify files exist:
```bash
ls -lh backend/models/buffalo_l/
# Should show det_10g.onnx and w600k_r50.onnx
```

- [ ] **Step 5: Enable pgvector in PostgreSQL**

Connect to the PostgreSQL database and run:
```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Verify:
```sql
SELECT * FROM pg_extension WHERE extname = 'vector';
-- Should return one row
```

- [ ] **Step 6: Commit**

```bash
git add backend/models/buffalo_l/.gitkeep backend/.gitignore backend/package.json backend/package-lock.json
git commit -m "chore: add onnxruntime-node, sharp deps + buffalo_l model directory"
```

---

## Task 2: FaceProfile Entity

**Files:**
- Create: `backend/src/core/database/entities/face-profile.entity.ts`
- Modify: `backend/src/core/database/entities/index.ts`
- Modify: `backend/src/core/database/database.module.ts`

- [ ] **Step 1: Write failing test**

Create `backend/src/core/database/entities/face-profile.entity.spec.ts`:
```typescript
import { FaceProfile } from './face-profile.entity';

describe('FaceProfile entity', () => {
  it('should instantiate with required fields', () => {
    const fp = new FaceProfile();
    fp.name = 'Hendra';
    fp.userId = 'user-uuid';
    fp.embedding = new Array(512).fill(0.1);
    expect(fp.name).toBe('Hendra');
    expect(fp.embedding).toHaveLength(512);
  });
});
```

Run: `cd backend && npx jest face-profile.entity.spec --no-coverage`
Expected: FAIL with "Cannot find module"

- [ ] **Step 2: Create FaceProfile entity**

Create `backend/src/core/database/entities/face-profile.entity.ts`:
```typescript
import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  ManyToOne,
  JoinColumn,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from './user.entity';

@Entity('face_profiles')
@Index(['userId'])
export class FaceProfile {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id' })
  userId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ length: 100 })
  name: string;

  // 512-dim ArcFace embedding stored as PostgreSQL float8 array.
  // Queried via pgvector cast: embedding::vector <=> $1::float8[]::vector
  @Column('float8', { array: true })
  embedding: number[];

  @Column({ name: 'thumbnail_url', nullable: true, length: 500 })
  thumbnailUrl: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
```

- [ ] **Step 3: Export from entities index**

Open `backend/src/core/database/entities/index.ts`. Add at end:
```typescript
export { FaceProfile } from './face-profile.entity';
```

- [ ] **Step 4: Register entity in DatabaseModule + pgvector init**

Open `backend/src/core/database/database.module.ts`. Modify the `entities` array and add afterConnect:
```typescript
import { FaceProfile } from './entities';

// In useFactory, add FaceProfile to entities array:
entities: [
  User,
  Device,
  Conversation,
  Message,
  Memory,
  ResponsePool,
  MoodEntry,
  FirmwareRelease,
  FaceProfile,  // ← add this
],
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd backend && npx jest face-profile.entity.spec --no-coverage
```
Expected: PASS

- [ ] **Step 6: Start backend and verify table created**

```bash
cd backend && npm run start:dev
```

Check logs for TypeORM synchronize output. Connect to DB and verify:
```sql
\d face_profiles
-- Should show id, user_id, name, embedding (float8[]), thumbnail_url, created_at, updated_at
```

- [ ] **Step 7: Commit**

```bash
git add backend/src/core/database/entities/face-profile.entity.ts \
        backend/src/core/database/entities/face-profile.entity.spec.ts \
        backend/src/core/database/entities/index.ts \
        backend/src/core/database/database.module.ts
git commit -m "feat(vision): add FaceProfile entity with float8[] embedding"
```

---

## Task 3: VisionInferenceService (buffalo_l ONNX)

**Files:**
- Create: `backend/src/modules/vision/vision-inference.service.ts`
- Create: `backend/src/modules/vision/vision-inference.service.spec.ts`

This service loads det_10g.onnx (SCRFD-10G face detector) and w600k_r50.onnx (ArcFace R50 embedder) once on startup, exposes `detect(jpegBuffer)` and `embed(jpegBuffer, box)` methods.

- [ ] **Step 1: Write failing test**

Create `backend/src/modules/vision/vision-inference.service.spec.ts`:
```typescript
import { VisionInferenceService } from './vision-inference.service';

// Heavy ONNX models not loaded in unit tests — all inference is mocked
jest.mock('onnxruntime-node', () => ({
  InferenceSession: {
    create: jest.fn().mockResolvedValue({
      run: jest.fn(),
      outputNames: ['score_8', 'score_16', 'score_32', 'bbox_8', 'bbox_16', 'bbox_32', 'kps_8', 'kps_16', 'kps_32'],
    }),
  },
  Tensor: jest.fn().mockImplementation((type, data, dims) => ({ type, data, dims })),
}));

jest.mock('sharp', () =>
  jest.fn().mockReturnValue({
    resize: jest.fn().mockReturnThis(),
    extract: jest.fn().mockReturnThis(),
    raw: jest.fn().mockReturnThis(),
    toBuffer: jest.fn().mockResolvedValue({
      data: Buffer.alloc(640 * 640 * 3, 128),
      info: { width: 640, height: 640, channels: 3 },
    }),
  }),
);

describe('VisionInferenceService', () => {
  let service: VisionInferenceService;

  beforeEach(() => {
    service = new VisionInferenceService();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  it('toNchw should produce correct shape', () => {
    const buf = Buffer.alloc(4 * 3, 100); // 2x2 RGB image
    const result = (service as any).toNchw(buf, 2, 2);
    expect(result).toHaveLength(3 * 4); // 3 channels * 4 pixels
    // Normalized: (100 - 127.5) / 128 = -0.21484375
    expect(result[0]).toBeCloseTo(-0.215, 2);
  });

  it('l2Normalize should produce unit vector', () => {
    const v = new Float32Array([3, 4]);
    const normalized = (service as any).l2Normalize(v);
    const norm = Math.sqrt(normalized[0] ** 2 + normalized[1] ** 2);
    expect(norm).toBeCloseTo(1.0, 5);
  });
});
```

Run: `cd backend && npx jest vision-inference.service.spec --no-coverage`
Expected: FAIL with "Cannot find module './vision-inference.service'"

- [ ] **Step 2: Create VisionInferenceService**

Create `backend/src/modules/vision/vision-inference.service.ts`:
```typescript
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as ort from 'onnxruntime-node';
import sharp from 'sharp';
import { join } from 'path';

export interface DetectedFace {
  box: [number, number, number, number]; // x1, y1, x2, y2 (original image coords)
  score: number;
}

@Injectable()
export class VisionInferenceService implements OnModuleInit {
  private readonly logger = new Logger(VisionInferenceService.name);
  private detSession: ort.InferenceSession | null = null;
  private recSession: ort.InferenceSession | null = null;

  private readonly MODEL_DIR = join(process.cwd(), 'models', 'buffalo_l');
  private readonly DET_MODEL = join(this.MODEL_DIR, 'det_10g.onnx');
  private readonly REC_MODEL = join(this.MODEL_DIR, 'w600k_r50.onnx');

  // SCRFD strides and num anchors per spatial location
  private readonly STRIDES = [8, 16, 32];
  private readonly NUM_ANCHORS = 2;
  private readonly DET_SIZE = 640;
  private readonly SCORE_THRESH = 0.5;

  async onModuleInit() {
    this.logger.log('Loading buffalo_l ONNX models...');
    try {
      this.detSession = await ort.InferenceSession.create(this.DET_MODEL, {
        executionProviders: ['cpu'],
      });
      this.recSession = await ort.InferenceSession.create(this.REC_MODEL, {
        executionProviders: ['cpu'],
      });
      this.logger.log('buffalo_l models loaded');
    } catch (err) {
      this.logger.error(`Failed to load models: ${(err as Error).message}`);
      this.logger.warn('Face recognition will be unavailable');
    }
  }

  /** Detect the highest-scoring face in a JPEG buffer. Returns null if no face found. */
  async detect(jpegBuffer: Buffer): Promise<DetectedFace | null> {
    if (!this.detSession) return null;

    const { data, info } = await sharp(jpegBuffer)
      .resize(this.DET_SIZE, this.DET_SIZE, { fit: 'fill' })
      .raw()
      .toBuffer({ resolveWithObject: true });

    const nchw = this.toNchw(data, this.DET_SIZE, this.DET_SIZE);
    const inputTensor = new ort.Tensor('float32', nchw, [1, 3, this.DET_SIZE, this.DET_SIZE]);
    const outputs = await this.detSession.run({ 'input.1': inputTensor });

    const scaleX = info.width / this.DET_SIZE;
    const scaleY = info.height / this.DET_SIZE;
    return this.parseBestDetection(outputs, scaleX, scaleY);
  }

  /** Crop the detected face, resize to 112x112, run ArcFace, return L2-normalized 512-dim embedding. */
  async embed(jpegBuffer: Buffer, box: [number, number, number, number]): Promise<number[] | null> {
    if (!this.recSession) return null;

    const [x1, y1, x2, y2] = box.map(Math.round);
    const width = Math.max(1, x2 - x1);
    const height = Math.max(1, y2 - y1);

    const { data } = await sharp(jpegBuffer)
      .extract({ left: x1, top: y1, width, height })
      .resize(112, 112)
      .raw()
      .toBuffer({ resolveWithObject: true });

    const nchw = this.toNchw(data, 112, 112);
    const inputTensor = new ort.Tensor('float32', nchw, [1, 3, 112, 112]);
    const outputs = await this.recSession.run({ 'input.1': inputTensor });

    // ArcFace R50 output name is '683' (output of last FC layer)
    const outputKey = Object.keys(outputs)[0];
    const embedding = outputs[outputKey].data as Float32Array;
    return this.l2Normalize(embedding);
  }

  /** Convert interleaved RGB Buffer to NCHW Float32Array normalized with mean=127.5 std=128. */
  private toNchw(buf: Buffer, width: number, height: number): Float32Array {
    const pixels = width * height;
    const nchw = new Float32Array(3 * pixels);
    for (let i = 0; i < pixels; i++) {
      nchw[i] = (buf[i * 3] - 127.5) / 128;
      nchw[pixels + i] = (buf[i * 3 + 1] - 127.5) / 128;
      nchw[2 * pixels + i] = (buf[i * 3 + 2] - 127.5) / 128;
    }
    return nchw;
  }

  /** L2-normalize a Float32Array to unit length. */
  private l2Normalize(embedding: Float32Array): number[] {
    const norm = Math.sqrt(Array.from(embedding).reduce((s, v) => s + v * v, 0));
    return norm > 0 ? Array.from(embedding).map(v => v / norm) : Array.from(embedding);
  }

  /**
   * Parse SCRFD outputs across all strides, return highest-scoring face.
   * SCRFD bbox outputs encode distances from anchor center: [left, top, right, bottom].
   */
  private parseBestDetection(
    outputs: Record<string, ort.Tensor>,
    scaleX: number,
    scaleY: number,
  ): DetectedFace | null {
    let best: DetectedFace | null = null;

    for (const stride of this.STRIDES) {
      const fH = Math.ceil(this.DET_SIZE / stride);
      const fW = Math.ceil(this.DET_SIZE / stride);
      const totalAnchors = fH * fW * this.NUM_ANCHORS;

      const scores = outputs[`score_${stride}`]?.data as Float32Array | undefined;
      const boxes = outputs[`bbox_${stride}`]?.data as Float32Array | undefined;
      if (!scores || !boxes) continue;

      for (let i = 0; i < totalAnchors; i++) {
        const score = scores[i];
        if (score < this.SCORE_THRESH) continue;

        // Anchor center in input (640x640) space
        const anchorIdx = Math.floor(i / this.NUM_ANCHORS);
        const cx = ((anchorIdx % fW) + 0.5) * stride;
        const cy = (Math.floor(anchorIdx / fW) + 0.5) * stride;

        // Decode box (distances from center, scaled by stride)
        const x1 = (cx - boxes[i * 4] * stride) * scaleX;
        const y1 = (cy - boxes[i * 4 + 1] * stride) * scaleY;
        const x2 = (cx + boxes[i * 4 + 2] * stride) * scaleX;
        const y2 = (cy + boxes[i * 4 + 3] * stride) * scaleY;

        if (!best || score > best.score) {
          best = { box: [x1, y1, x2, y2], score };
        }
      }
    }

    return best;
  }
}
```

- [ ] **Step 3: Run test**

```bash
cd backend && npx jest vision-inference.service.spec --no-coverage
```
Expected: PASS (4 tests)

- [ ] **Step 4: Commit**

```bash
git add backend/src/modules/vision/vision-inference.service.ts \
        backend/src/modules/vision/vision-inference.service.spec.ts
git commit -m "feat(vision): add VisionInferenceService with buffalo_l ONNX (det + embed)"
```

---

## Task 4: VisionService (Enrollment + Recognition)

**Files:**
- Create: `backend/src/modules/vision/vision.service.ts`
- Create: `backend/src/modules/vision/vision.service.spec.ts`

- [ ] **Step 1: Write failing test**

Create `backend/src/modules/vision/vision.service.spec.ts`:
```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import { getRepositoryToken } from '@nestjs/typeorm';
import { VisionService } from './vision.service';
import { VisionInferenceService } from './vision-inference.service';
import { FaceProfile } from '../../core/database/entities/face-profile.entity';

const mockInference = {
  detect: jest.fn(),
  embed: jest.fn(),
};

const mockRepo = {
  find: jest.fn(),
  findOne: jest.fn(),
  create: jest.fn(),
  save: jest.fn(),
  delete: jest.fn(),
};

const mockDataSource = {
  query: jest.fn(),
};

describe('VisionService', () => {
  let service: VisionService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        VisionService,
        { provide: VisionInferenceService, useValue: mockInference },
        { provide: getRepositoryToken(FaceProfile), useValue: mockRepo },
        { provide: DataSource, useValue: mockDataSource },
      ],
    }).compile();
    service = module.get(VisionService);
    jest.clearAllMocks();
  });

  describe('enroll', () => {
    it('should detect face, compute embedding, and save profile', async () => {
      const fakeEmbedding = new Array(512).fill(0.1);
      mockInference.detect.mockResolvedValue({ box: [10, 10, 100, 100], score: 0.9 });
      mockInference.embed.mockResolvedValue(fakeEmbedding);
      mockRepo.create.mockReturnValue({ name: 'Hendra', userId: 'u1', embedding: fakeEmbedding });
      mockRepo.save.mockResolvedValue({ id: 'fp-uuid', name: 'Hendra' });

      const result = await service.enroll('u1', 'Hendra', [Buffer.from('jpeg')]);
      expect(mockInference.detect).toHaveBeenCalledTimes(1);
      expect(mockInference.embed).toHaveBeenCalledTimes(1);
      expect(mockRepo.save).toHaveBeenCalledTimes(1);
      expect(result.name).toBe('Hendra');
    });

    it('should throw if no face detected in any frame', async () => {
      mockInference.detect.mockResolvedValue(null);
      await expect(service.enroll('u1', 'Hendra', [Buffer.from('jpeg')])).rejects.toThrow(
        'No face detected',
      );
    });
  });

  describe('findBestMatch', () => {
    it('should return name when distance below threshold', async () => {
      mockDataSource.query.mockResolvedValue([{ id: 'fp1', name: 'Hendra', distance: '0.3' }]);
      const result = await service.findBestMatch('u1', new Array(512).fill(0.1));
      expect(result).toEqual({ name: 'Hendra', confidence: expect.any(Number), unknown: false });
    });

    it('should return unknown when distance above threshold', async () => {
      mockDataSource.query.mockResolvedValue([{ id: 'fp1', name: 'Hendra', distance: '0.55' }]);
      const result = await service.findBestMatch('u1', new Array(512).fill(0.1));
      expect(result).toEqual({ name: null, confidence: expect.any(Number), unknown: true });
    });

    it('should return unknown when no profiles exist', async () => {
      mockDataSource.query.mockResolvedValue([]);
      const result = await service.findBestMatch('u1', new Array(512).fill(0.1));
      expect(result).toEqual({ name: null, confidence: 0, unknown: true });
    });
  });

  describe('getProfiles', () => {
    it('should return profiles for user', async () => {
      mockRepo.find.mockResolvedValue([{ id: 'fp1', name: 'Hendra' }]);
      const result = await service.getProfiles('u1');
      expect(mockRepo.find).toHaveBeenCalledWith({ where: { userId: 'u1' }, order: { createdAt: 'ASC' } });
      expect(result).toHaveLength(1);
    });
  });

  describe('deleteProfile', () => {
    it('should delete when owned by user', async () => {
      mockRepo.findOne.mockResolvedValue({ id: 'fp1', userId: 'u1' });
      mockRepo.delete.mockResolvedValue({ affected: 1 });
      await service.deleteProfile('u1', 'fp1');
      expect(mockRepo.delete).toHaveBeenCalledWith('fp1');
    });

    it('should throw when profile not found or wrong user', async () => {
      mockRepo.findOne.mockResolvedValue(null);
      await expect(service.deleteProfile('u1', 'fp1')).rejects.toThrow();
    });
  });
});
```

Run: `cd backend && npx jest vision.service.spec --no-coverage`
Expected: FAIL with "Cannot find module './vision.service'"

- [ ] **Step 2: Create VisionService**

Create `backend/src/modules/vision/vision.service.ts`:
```typescript
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
```

- [ ] **Step 3: Run test**

```bash
cd backend && npx jest vision.service.spec --no-coverage
```
Expected: PASS (all tests)

- [ ] **Step 4: Commit**

```bash
git add backend/src/modules/vision/vision.service.ts \
        backend/src/modules/vision/vision.service.spec.ts
git commit -m "feat(vision): add VisionService (enrollment + pgvector recognition)"
```

---

## Task 5: VisionController (REST API)

**Files:**
- Create: `backend/src/modules/vision/dto/enroll-face.dto.ts`
- Create: `backend/src/modules/vision/vision.controller.ts`
- Create: `backend/src/modules/vision/vision.controller.spec.ts`

- [ ] **Step 1: Write failing test**

Create `backend/src/modules/vision/vision.controller.spec.ts`:
```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { VisionController } from './vision.controller';
import { VisionService } from './vision.service';
import { AudioGateway } from '../gateway/audio.gateway';

const mockVisionService = {
  enroll: jest.fn(),
  getProfiles: jest.fn(),
  deleteProfile: jest.fn(),
};

const mockGateway = {
  sendVisionCapture: jest.fn(),
};

const mockUser = { id: 'user-uuid', email: 'test@test.com' };

describe('VisionController', () => {
  let controller: VisionController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [VisionController],
      providers: [
        { provide: VisionService, useValue: mockVisionService },
        { provide: AudioGateway, useValue: mockGateway },
      ],
    }).compile();
    controller = module.get(VisionController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  describe('getProfiles', () => {
    it('should return profiles for current user', async () => {
      mockVisionService.getProfiles.mockResolvedValue([{ id: 'fp1', name: 'Hendra' }]);
      const result = await controller.getProfiles({ user: mockUser } as any);
      expect(mockVisionService.getProfiles).toHaveBeenCalledWith('user-uuid');
      expect(result).toHaveLength(1);
    });
  });

  describe('deleteProfile', () => {
    it('should delete profile', async () => {
      mockVisionService.deleteProfile.mockResolvedValue(undefined);
      await controller.deleteProfile({ user: mockUser } as any, 'fp1');
      expect(mockVisionService.deleteProfile).toHaveBeenCalledWith('user-uuid', 'fp1');
    });
  });
});
```

Run: `cd backend && npx jest vision.controller.spec --no-coverage`
Expected: FAIL with "Cannot find module './vision.controller'"

- [ ] **Step 2: Create EnrollFaceDto**

Create `backend/src/modules/vision/dto/enroll-face.dto.ts`:
```typescript
import { IsString, Length } from 'class-validator';

export class EnrollFaceDto {
  @IsString()
  @Length(1, 100)
  name: string;
}
```

- [ ] **Step 3: Create VisionController**

Create `backend/src/modules/vision/vision.controller.ts`:
```typescript
import {
  Controller,
  Post,
  Get,
  Delete,
  Param,
  Query,
  Body,
  Request,
  UploadedFiles,
  UseGuards,
  UseInterceptors,
  HttpCode,
  HttpStatus,
  ParseUUIDPipe,
  BadRequestException,
} from '@nestjs/common';
import { FilesInterceptor } from '@nestjs/platform-express';
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
    // Store pending enrollment so gateway handler can pick it up when frames arrive
    this.gateway.setPendingEnrollment(cameraDeviceId, req.user.id, dto.name);
    this.gateway.sendVisionCapture(cameraDeviceId);
    return { ok: true, message: 'Capture triggered — awaiting frames from camera' };
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
```

- [ ] **Step 4: Run test**

```bash
cd backend && npx jest vision.controller.spec --no-coverage
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/vision/dto/enroll-face.dto.ts \
        backend/src/modules/vision/vision.controller.ts \
        backend/src/modules/vision/vision.controller.spec.ts
git commit -m "feat(vision): add VisionController (enroll, profiles, capture trigger)"
```

---

## Task 6: VisionGatewayHandler + AudioGateway Integration

**Files:**
- Create: `backend/src/modules/vision/vision-gateway.handler.ts`
- Modify: `backend/src/modules/gateway/audio.gateway.ts`
- Modify: `backend/src/modules/gateway/session.manager.ts`

The gateway already parses raw WebSocket messages and dispatches by event name. Add vision:frame and vision:enroll_frames cases.

- [ ] **Step 1: Add currentIdentity to DeviceSession**

Open `backend/src/modules/gateway/session.manager.ts`. Add to the `DeviceSession` interface (after `skipGreeting`):

```typescript
/** Identity of the person currently in frame, updated by face recognition. */
currentIdentity?: { name: string | null; unknown: boolean } | null;
```

Also add a setter method at the bottom of the `SessionManager` class:
```typescript
setCurrentIdentity(deviceId: string, identity: { name: string | null; unknown: boolean } | null): void {
  const session = this.sessions.get(deviceId);
  if (session) session.currentIdentity = identity;
}
```

- [ ] **Step 2: Create VisionGatewayHandler**

Create `backend/src/modules/vision/vision-gateway.handler.ts`:
```typescript
import { Injectable, Logger } from '@nestjs/common';
import { VisionService } from './vision.service';
import { SessionManager } from '../gateway/session.manager';
import { DevicesService } from '../devices/devices.service';

export interface PendingEnrollment {
  userId: string;
  name: string;
  frames: Buffer[];
}

@Injectable()
export class VisionGatewayHandler {
  private readonly logger = new Logger(VisionGatewayHandler.name);
  private sendFn: ((deviceId: string, event: string, data: any) => void) | null = null;
  private pendingEnrollments = new Map<string, PendingEnrollment>();

  constructor(
    private readonly visionService: VisionService,
    private readonly sessions: SessionManager,
    private readonly devicesService: DevicesService,
  ) {}

  setSendFn(fn: (deviceId: string, event: string, data: any) => void) {
    this.sendFn = fn;
  }

  /** Called by AudioGateway when a vision:frame binary message arrives. */
  async handleFrame(cameraDeviceId: string, jpegBuffer: Buffer): Promise<void> {
    // Get camera device settings to find paired aksabot device
    const device = await this.devicesService.findById(cameraDeviceId);
    if (!device) return;

    const userId = device.userId;
    const pairedDeviceId = device.settingsJson?.pairedDeviceId as string | undefined;

    // Run face recognition
    const embedding = await this.visionService.detectAndEmbed(jpegBuffer);
    if (!embedding) {
      // No face in frame — clear identity on paired device
      if (pairedDeviceId) {
        this.sessions.setCurrentIdentity(pairedDeviceId, null);
      }
      return;
    }

    const identity = await this.visionService.findBestMatch(userId, embedding);
    this.logger.debug(
      `Face match: ${identity.unknown ? 'unknown' : identity.name} (conf=${identity.confidence.toFixed(2)})`,
    );

    // Update session identity on paired aksabot device
    if (pairedDeviceId) {
      this.sessions.setCurrentIdentity(pairedDeviceId, {
        name: identity.name,
        unknown: identity.unknown,
      });

      // Push face:identity event to paired aksabot device
      this.sendFn?.(pairedDeviceId, 'face:identity', {
        name: identity.name,
        confidence: identity.confidence,
        unknown: identity.unknown,
      });
    }
  }

  /** Called by AudioGateway when vision:enroll_frames arrives (8 frames from live capture). */
  async handleEnrollFrames(cameraDeviceId: string, jpegFrames: Buffer[]): Promise<void> {
    const pending = this.pendingEnrollments.get(cameraDeviceId);
    if (!pending) {
      this.logger.warn(`Received enroll frames for ${cameraDeviceId} but no pending enrollment`);
      return;
    }
    this.pendingEnrollments.delete(cameraDeviceId);

    try {
      const profile = await this.visionService.enroll(pending.userId, pending.name, jpegFrames);
      this.logger.log(`Live capture enrollment complete: ${profile.name} (id=${profile.id})`);
      this.sendFn?.(cameraDeviceId, 'vision:enroll_result', { ok: true, name: profile.name });
    } catch (err) {
      this.logger.warn(`Live capture enrollment failed: ${(err as Error).message}`);
      this.sendFn?.(cameraDeviceId, 'vision:enroll_result', { ok: false, error: (err as Error).message });
    }
  }

  setPendingEnrollment(cameraDeviceId: string, userId: string, name: string): void {
    this.pendingEnrollments.set(cameraDeviceId, { userId, name, frames: [] });
  }
}
```

- [ ] **Step 3: Modify AudioGateway to inject VisionGatewayHandler**

Open `backend/src/modules/gateway/audio.gateway.ts`.

Add import at top:
```typescript
import { VisionGatewayHandler } from '../vision/vision-gateway.handler';
```

Add to constructor parameters:
```typescript
private readonly visionHandler: VisionGatewayHandler,
```

In `onModuleInit()`, after the existing `setSendToDevice` calls, add:
```typescript
this.visionHandler.setSendFn((deviceId, event, data) =>
  this.sendToDevice(deviceId, event, data),
);
```

In the `handleMessage` method, add vision event cases. Find the switch/if-else that dispatches by `msg.event` and add:
```typescript
case 'vision:frame':
  // msg.data is base64-encoded JPEG
  if (typeof msg.data === 'string') {
    const jpeg = Buffer.from(msg.data, 'base64');
    this.visionHandler.handleFrame(deviceId, jpeg).catch(err =>
      this.logger.warn(`vision:frame error: ${err.message}`),
    );
  }
  break;

case 'vision:enroll_frames':
  // msg.data is array of base64-encoded JPEGs
  if (Array.isArray(msg.data)) {
    const frames = msg.data.map((b64: string) => Buffer.from(b64, 'base64'));
    this.visionHandler.handleEnrollFrames(deviceId, frames).catch(err =>
      this.logger.warn(`vision:enroll_frames error: ${err.message}`),
    );
  }
  break;
```

Add helper methods to AudioGateway (called by VisionController):
```typescript
sendVisionCapture(cameraDeviceId: string): void {
  this.sendToDevice(cameraDeviceId, 'vision:capture', {});
}

setPendingEnrollment(cameraDeviceId: string, userId: string, name: string): void {
  this.visionHandler.setPendingEnrollment(cameraDeviceId, userId, name);
}
```

- [ ] **Step 4: Inject identity into LLM system prompt**

In `audio.gateway.ts`, find where the system prompt / LLM context is built (look for where AiService is called with a system prompt or context). Add identity injection before calling the AI:

```typescript
// Add this helper method to AudioGateway:
private buildIdentityContext(deviceId: string): string {
  const session = this.sessions.get(deviceId);
  const identity = session?.currentIdentity;
  if (!identity) return '';
  if (identity.unknown) return 'An unknown person is currently present at the desk.';
  return `${identity.name} is currently present at the desk.`;
}
```

Then in the system prompt construction, append `this.buildIdentityContext(deviceId)` to the context string. Look for the call to `this.aiService` or `this.proactive` that builds system context, and add the identity context line there.

- [ ] **Step 5: Build and verify no TypeScript errors**

```bash
cd backend && npx tsc --noEmit
```
Expected: No errors. Fix any type errors before committing.

- [ ] **Step 6: Commit**

```bash
git add backend/src/modules/vision/vision-gateway.handler.ts \
        backend/src/modules/gateway/session.manager.ts \
        backend/src/modules/gateway/audio.gateway.ts
git commit -m "feat(vision): add VisionGatewayHandler, vision:frame WS events, identity context injection"
```

---

## Task 7: VisionModule + App Registration

**Files:**
- Create: `backend/src/modules/vision/vision.module.ts`
- Modify: `backend/src/modules/gateway/gateway.module.ts`
- Modify: `backend/src/app.module.ts`

- [ ] **Step 1: Create VisionModule**

Create `backend/src/modules/vision/vision.module.ts`:
```typescript
import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MulterModule } from '@nestjs/platform-express';
import { FaceProfile } from '../../core/database/entities/face-profile.entity';
import { VisionInferenceService } from './vision-inference.service';
import { VisionService } from './vision.service';
import { VisionController } from './vision.controller';
import { VisionGatewayHandler } from './vision-gateway.handler';
import { GatewayModule } from '../gateway/gateway.module';
import { DevicesModule } from '../devices/devices.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([FaceProfile]),
    MulterModule.register({ storage: undefined }), // in-memory (buffer) storage
    forwardRef(() => GatewayModule),
    DevicesModule,
  ],
  controllers: [VisionController],
  providers: [VisionInferenceService, VisionService, VisionGatewayHandler],
  exports: [VisionService, VisionGatewayHandler],
})
export class VisionModule {}
```

- [ ] **Step 2: Update GatewayModule to import VisionModule**

Open `backend/src/modules/gateway/gateway.module.ts`.

Add import:
```typescript
import { VisionModule } from '../vision/vision.module';
```

Add to `imports` array:
```typescript
forwardRef(() => VisionModule),
```

Add `VisionGatewayHandler` to `providers` array:
```typescript
import { VisionGatewayHandler } from '../vision/vision-gateway.handler';
// In providers:
VisionGatewayHandler,
```

- [ ] **Step 3: Register VisionModule in app.module.ts**

Open `backend/src/app.module.ts`. Add:
```typescript
import { VisionModule } from './modules/vision/vision.module';

// In imports array:
VisionModule,
```

- [ ] **Step 4: Build and start backend**

```bash
cd backend && npx tsc --noEmit
npm run start:dev
```

Expected: Backend starts, logs show:
```
[VisionInferenceService] Loading buffalo_l ONNX models...
[VisionInferenceService] buffalo_l models loaded
```

If models not found: `Failed to load models` warning — expected during development without model files.

- [ ] **Step 5: Run all vision tests**

```bash
cd backend && npx jest vision --no-coverage
```
Expected: All tests pass.

- [ ] **Step 6: Run full test suite**

```bash
cd backend && npm test
```
Expected: All 215+ existing tests still pass + new vision tests.

- [ ] **Step 7: Commit**

```bash
git add backend/src/modules/vision/vision.module.ts \
        backend/src/modules/gateway/gateway.module.ts \
        backend/src/app.module.ts
git commit -m "feat(vision): wire VisionModule into app — backend face recognition complete"
```

---

## Self-Review

**Spec coverage:**
- ✅ buffalo_l ONNX inference (det_10g + w600k_r50) — Task 3
- ✅ pgvector cosine similarity search — Task 4
- ✅ Enrollment API (POST /vision/enroll, GET /vision/profiles, DELETE) — Task 5
- ✅ ESP32-CAM capture trigger (POST /vision/enroll/capture) — Task 5/6
- ✅ vision:frame WS handler — Task 6
- ✅ vision:enroll_frames WS handler — Task 6
- ✅ face:identity push to paired aksabot device — Task 6
- ✅ currentIdentity in SessionManager — Task 6
- ✅ LLM context injection (known/unknown person) — Task 6
- ✅ vision:capture outbound event — Task 6
- ✅ pairedDeviceId routing via device settingsJson — Task 6
