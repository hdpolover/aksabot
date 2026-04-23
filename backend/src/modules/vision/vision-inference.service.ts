import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as ort from 'onnxruntime-node';
import sharp from 'sharp';
import { join } from 'path';

export interface DetectedFace {
  box: [number, number, number, number]; // x1, y1, x2, y2 in original image coords
  score: number;
  keypoints: [number, number][]; // 5 landmarks: left_eye, right_eye, nose, left_mouth, right_mouth
}

@Injectable()
export class VisionInferenceService implements OnModuleInit {
  private readonly logger = new Logger(VisionInferenceService.name);
  private detSession: ort.InferenceSession | null = null;
  private recSession: ort.InferenceSession | null = null;

  private readonly MODEL_DIR = join(process.cwd(), 'models', 'buffalo_l');
  private readonly DET_MODEL = join(this.MODEL_DIR, 'det_10g.onnx');
  private readonly REC_MODEL = join(this.MODEL_DIR, 'w600k_r50.onnx');

  private readonly STRIDES = [8, 16, 32];
  private readonly NUM_ANCHORS = 2;
  private readonly DET_SIZE = 640;
  private readonly SCORE_THRESH = 0.45;
  /** Minimum face width in original image pixels — skip tiny/distant faces. */
  private readonly MIN_FACE_PX = 48;

  // buffalo_l det_10g.onnx numeric output node names (verified by shape analysis):
  // stride 8:  448=score [N,1], 451=bbox [N,4], 454=kps [N,10]
  // stride 16: 471=score,       474=bbox,        477=kps
  // stride 32: 494=score,       497=bbox,        500=kps
  private readonly SCORE_KEYS = ['448', '471', '494'];
  private readonly BBOX_KEYS  = ['451', '474', '497'];
  private readonly KPS_KEYS   = ['454', '477', '500'];

  // ArcFace 112×112 standard template — where the 5 landmarks land after alignment.
  private readonly ARCFACE_TEMPLATE: [number, number][] = [
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
  ];

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

  /** Detect ALL faces above threshold, sorted by score descending. */
  async detectAll(jpegBuffer: Buffer): Promise<DetectedFace[]> {
    if (!this.detSession) return [];

    const origMeta = await sharp(jpegBuffer).metadata();
    const origW = origMeta.width ?? this.DET_SIZE;
    const origH = origMeta.height ?? this.DET_SIZE;

    const { data } = await sharp(jpegBuffer)
      .resize(this.DET_SIZE, this.DET_SIZE, { fit: 'fill' })
      .raw()
      .toBuffer({ resolveWithObject: true });

    const nchw = this.toNchw(data, this.DET_SIZE, this.DET_SIZE);
    const inputTensor = new ort.Tensor('float32', nchw, [1, 3, this.DET_SIZE, this.DET_SIZE]);
    const outputs = await this.detSession.run({ 'input.1': inputTensor });

    const scaleX = origW / this.DET_SIZE;
    const scaleY = origH / this.DET_SIZE;
    return this.parseAllDetections(outputs, scaleX, scaleY);
  }

  /** Convenience: detect single highest-scoring face (used by enroll). */
  async detect(jpegBuffer: Buffer): Promise<DetectedFace | null> {
    const all = await this.detectAll(jpegBuffer);
    return all[0] ?? null;
  }

  /**
   * Align face to ArcFace 112×112 template using 5-point similarity transform,
   * then run ArcFace R50 to produce a 512-dim L2-normalised embedding.
   */
  async embed(jpegBuffer: Buffer, detection: DetectedFace): Promise<number[] | null> {
    if (!this.recSession) return null;

    const faceData = detection.keypoints.length === 5
      ? await this.alignFace(jpegBuffer, detection.keypoints)
      : await this.cropFace(jpegBuffer, detection.box);

    const nchw = this.toNchw(faceData, 112, 112);
    const inputTensor = new ort.Tensor('float32', nchw, [1, 3, 112, 112]);
    const outputs = await this.recSession.run({ 'input.1': inputTensor });
    return this.l2Normalize(outputs[Object.keys(outputs)[0]].data as Float32Array);
  }

  /**
   * Produce a 48×48 JPEG thumbnail from the aligned face (for profile display).
   * Returns null if alignment fails.
   */
  async thumbnail(jpegBuffer: Buffer, detection: DetectedFace): Promise<Buffer | null> {
    try {
      const aligned = detection.keypoints.length === 5
        ? await this.alignFace(jpegBuffer, detection.keypoints)
        : await this.cropFace(jpegBuffer, detection.box);

      return sharp(aligned, { raw: { width: 112, height: 112, channels: 3 } })
        .resize(48, 48)
        .jpeg({ quality: 60 })
        .toBuffer();
    } catch {
      return null;
    }
  }

  /**
   * Warp face to ArcFace 112×112 standard template using bilinear interpolation.
   * Computes similarity transform (Umeyama): detected landmarks → template positions.
   */
  private async alignFace(jpegBuffer: Buffer, keypoints: [number, number][]): Promise<Buffer> {
    const { a, b, tx, ty } = this.similarityTransform(keypoints, this.ARCFACE_TEMPLATE);

    // Inverse transform: template coords → source image coords
    const det = a * a + b * b;
    const ai = a / det, bi = b / det;
    const txi = -ai * tx - bi * ty;
    const tyi =  bi * tx - ai * ty;

    const { data: src, info } = await sharp(jpegBuffer).raw().toBuffer({ resolveWithObject: true });
    const W = info.width, H = info.height, C = info.channels;

    const out = Buffer.alloc(112 * 112 * 3, 0);
    for (let oy = 0; oy < 112; oy++) {
      for (let ox = 0; ox < 112; ox++) {
        const fx = ai * ox + bi * oy + txi;
        const fy = -bi * ox + ai * oy + tyi;
        const [r, g, b_] = this.sampleBilinear(src, W, H, C, fx, fy);
        const di = (oy * 112 + ox) * 3;
        out[di] = r; out[di + 1] = g; out[di + 2] = b_;
      }
    }
    return out;
  }

  /** Bilinear sample at fractional coords (fx, fy). Returns [R, G, B]. */
  private sampleBilinear(
    src: Buffer, W: number, H: number, C: number, fx: number, fy: number,
  ): [number, number, number] {
    const x0 = Math.floor(fx), y0 = Math.floor(fy);
    if (x0 < 0 || y0 < 0 || x0 >= W || y0 >= H) return [0, 0, 0];
    const x1 = Math.min(x0 + 1, W - 1), y1 = Math.min(y0 + 1, H - 1);
    const dx = fx - x0, dy = fy - y0;
    const s = (y: number, x: number, c: number) => src[(y * W + x) * C + c];
    return [0, 1, 2].map(c =>
      s(y0, x0, c) * (1 - dx) * (1 - dy) +
      s(y0, x1, c) * dx * (1 - dy) +
      s(y1, x0, c) * (1 - dx) * dy +
      s(y1, x1, c) * dx * dy,
    ) as [number, number, number];
  }

  /** Fallback: simple crop + resize when keypoints unavailable. */
  private async cropFace(jpegBuffer: Buffer, box: [number, number, number, number]): Promise<Buffer> {
    const meta = await sharp(jpegBuffer).metadata();
    const W = meta.width ?? this.DET_SIZE, H = meta.height ?? this.DET_SIZE;
    const left   = Math.max(0, Math.round(box[0]));
    const top    = Math.max(0, Math.round(box[1]));
    const right  = Math.min(W, Math.round(box[2]));
    const bottom = Math.min(H, Math.round(box[3]));
    const { data } = await sharp(jpegBuffer)
      .extract({ left, top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) })
      .resize(112, 112)
      .raw()
      .toBuffer({ resolveWithObject: true });
    return data;
  }

  /**
   * Similarity transform via least-squares (Umeyama).
   * Returns [a, b, tx, ty] for: [dx,dy] = [[a,-b],[b,a]] * [sx,sy] + [tx,ty]
   */
  private similarityTransform(
    src: [number, number][],
    dst: [number, number][],
  ): { a: number; b: number; tx: number; ty: number } {
    const n = src.length;
    const smx = src.reduce((s, p) => s + p[0], 0) / n;
    const smy = src.reduce((s, p) => s + p[1], 0) / n;
    const dmx = dst.reduce((s, p) => s + p[0], 0) / n;
    const dmy = dst.reduce((s, p) => s + p[1], 0) / n;
    let numA = 0, numB = 0, denom = 0;
    for (let i = 0; i < n; i++) {
      const sx = src[i][0] - smx, sy = src[i][1] - smy;
      const dx = dst[i][0] - dmx, dy = dst[i][1] - dmy;
      numA  += sx * dx + sy * dy;
      numB  += sx * dy - sy * dx;
      denom += sx * sx + sy * sy;
    }
    const a = numA / denom, b = numB / denom;
    return { a, b, tx: dmx - a * smx + b * smy, ty: dmy - b * smx - a * smy };
  }

  /**
   * Convert interleaved RGB Buffer to BGR NCHW Float32Array.
   * InsightFace models expect BGR channel order, mean=127.5, std=128.
   */
  toNchw(buf: Buffer, width: number, height: number): Float32Array {
    const pixels = width * height;
    const nchw = new Float32Array(3 * pixels);
    for (let i = 0; i < pixels; i++) {
      const r = buf[i * 3], g = buf[i * 3 + 1], b = buf[i * 3 + 2];
      nchw[i]              = (b - 127.5) / 128;
      nchw[pixels + i]     = (g - 127.5) / 128;
      nchw[2 * pixels + i] = (r - 127.5) / 128;
    }
    return nchw;
  }

  /** L2-normalize a Float32Array to unit length. */
  l2Normalize(embedding: Float32Array): number[] {
    const norm = Math.sqrt(Array.from(embedding).reduce((s, v) => s + v * v, 0));
    return norm > 0 ? Array.from(embedding).map(v => v / norm) : Array.from(embedding);
  }

  /**
   * Parse SCRFD outputs → all DetectedFace entries above threshold,
   * filtered by minimum face size, sorted by score descending.
   */
  private parseAllDetections(
    outputs: Record<string, ort.Tensor>,
    scaleX: number,
    scaleY: number,
  ): DetectedFace[] {
    const faces: DetectedFace[] = [];

    for (let si = 0; si < this.STRIDES.length; si++) {
      const stride = this.STRIDES[si];
      const fH = Math.ceil(this.DET_SIZE / stride);
      const fW = Math.ceil(this.DET_SIZE / stride);
      const total = fH * fW * this.NUM_ANCHORS;

      const scores = outputs[this.SCORE_KEYS[si]]?.data as Float32Array | undefined;
      const boxes  = outputs[this.BBOX_KEYS[si]]?.data  as Float32Array | undefined;
      const kps    = outputs[this.KPS_KEYS[si]]?.data   as Float32Array | undefined;
      if (!scores || !boxes) continue;

      for (let i = 0; i < total; i++) {
        if (scores[i] < this.SCORE_THRESH) continue;

        const anchorIdx = Math.floor(i / this.NUM_ANCHORS);
        const cx = ((anchorIdx % fW) + 0.5) * stride;
        const cy = (Math.floor(anchorIdx / fW) + 0.5) * stride;

        const x1 = (cx - boxes[i * 4]     * stride) * scaleX;
        const y1 = (cy - boxes[i * 4 + 1] * stride) * scaleY;
        const x2 = (cx + boxes[i * 4 + 2] * stride) * scaleX;
        const y2 = (cy + boxes[i * 4 + 3] * stride) * scaleY;

        // Skip faces too small to get a reliable embedding
        if ((x2 - x1) < this.MIN_FACE_PX) continue;

        const keypoints: [number, number][] = [];
        if (kps) {
          for (let j = 0; j < 5; j++) {
            keypoints.push([
              (cx + kps[i * 10 + j * 2]     * stride) * scaleX,
              (cy + kps[i * 10 + j * 2 + 1] * stride) * scaleY,
            ]);
          }
        }

        faces.push({ box: [x1, y1, x2, y2], score: scores[i], keypoints });
      }
    }

    return this.nms(faces, 0.4);
  }

  /**
   * Non-Maximum Suppression: remove overlapping boxes for the same face.
   * Greedy algorithm: keep highest-score box, discard any box with IoU > threshold.
   * iouThresh=0.4 is standard for face detection.
   */
  private nms(faces: DetectedFace[], iouThresh: number): DetectedFace[] {
    const sorted = [...faces].sort((a, b) => b.score - a.score);
    const keep: DetectedFace[] = [];

    for (const face of sorted) {
      const [x1, y1, x2, y2] = face.box;
      const area = (x2 - x1) * (y2 - y1);
      const suppressed = keep.some(kept => {
        const [kx1, ky1, kx2, ky2] = kept.box;
        const ix = Math.max(0, Math.min(x2, kx2) - Math.max(x1, kx1));
        const iy = Math.max(0, Math.min(y2, ky2) - Math.max(y1, ky1));
        const inter = ix * iy;
        const kArea = (kx2 - kx1) * (ky2 - ky1);
        return inter / (area + kArea - inter) > iouThresh;
      });
      if (!suppressed) keep.push(face);
    }

    return keep;
  }
}
