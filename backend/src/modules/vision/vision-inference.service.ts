import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as ort from 'onnxruntime-node';
import sharp from 'sharp';
import { join } from 'path';

export interface DetectedFace {
  box: [number, number, number, number]; // x1, y1, x2, y2 (original image coords)
  score: number;
  /** 5 facial landmarks: [left_eye, right_eye, nose, left_mouth, right_mouth] */
  keypoints: [number, number][];
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
  private readonly SCORE_THRESH = 0.3;

  // buffalo_l det_10g.onnx numeric output node names (verified by shape):
  // stride 8:  448=score, 451=bbox, 454=kps
  // stride 16: 471=score, 474=bbox, 477=kps
  // stride 32: 494=score, 497=bbox, 500=kps
  private readonly SCORE_KEYS = ['448', '471', '494'];
  private readonly BBOX_KEYS  = ['451', '474', '497'];
  private readonly KPS_KEYS   = ['454', '477', '500'];

  // ArcFace standard 112×112 template — where the 5 landmarks should land after alignment.
  // Order: left_eye, right_eye, nose_tip, left_mouth, right_mouth
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

  /** Detect the highest-scoring face + 5-point landmarks. Returns null if no face found. */
  async detect(jpegBuffer: Buffer): Promise<DetectedFace | null> {
    if (!this.detSession) return null;

    // Get original size BEFORE resize — after resize, info.width/height are always DET_SIZE,
    // which makes scaleX=scaleY=1.0 and leaves coordinates stuck in 640x640 space.
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
    return this.parseBestDetection(outputs, scaleX, scaleY);
  }

  /**
   * Align face to ArcFace 112×112 template using the 5-point keypoints, then embed.
   * Alignment eliminates pose/scale variation — dramatically improves recognition accuracy.
   */
  async embed(jpegBuffer: Buffer, detection: DetectedFace): Promise<number[] | null> {
    if (!this.recSession) return null;

    let faceData: Buffer;

    if (detection.keypoints.length === 5) {
      this.logger.debug(`Aligning face with kps: ${JSON.stringify(detection.keypoints.map(p => p.map(v => Math.round(v))))}`);
      faceData = await this.alignFace(jpegBuffer, detection.keypoints);
    } else {
      // Fallback: simple crop (no keypoints available)
      faceData = await this.cropFace(jpegBuffer, detection.box);
    }

    const nchw = this.toNchw(faceData, 112, 112);
    const inputTensor = new ort.Tensor('float32', nchw, [1, 3, 112, 112]);
    const outputs = await this.recSession.run({ 'input.1': inputTensor });
    const outputKey = Object.keys(outputs)[0];
    return this.l2Normalize(outputs[outputKey].data as Float32Array);
  }

  /**
   * Align face to the ArcFace 112×112 standard template using a similarity transform
   * computed from the 5 detected landmarks. This is what ArcFace was trained to receive.
   *
   * For each output pixel (ox, oy), the inverse transform maps back to source image coords.
   * Nearest-neighbour sampling is fast and sufficient for ArcFace.
   */
  private async alignFace(jpegBuffer: Buffer, keypoints: [number, number][]): Promise<Buffer> {
    // Compute forward transform: landmark_coords → template_coords
    const { a, b, tx, ty } = this.similarityTransform(keypoints, this.ARCFACE_TEMPLATE);

    // Invert: template_coords → landmark_coords (for reverse-mapping each output pixel)
    // Forward: [dx,dy] = [[a,-b],[b,a]] * [sx,sy] + [tx,ty]
    // Inverse: [sx,sy] = [[a,b],[-b,a]] / det * ([dx,dy] - [tx,ty])
    const det = a * a + b * b;
    const ai = a / det, bi = b / det;
    const txi = -ai * tx - bi * ty;
    const tyi =  bi * tx - ai * ty;

    const { data: src, info } = await sharp(jpegBuffer)
      .raw()
      .toBuffer({ resolveWithObject: true });
    const W = info.width, H = info.height, C = info.channels;

    const out = Buffer.alloc(112 * 112 * 3, 0);
    for (let oy = 0; oy < 112; oy++) {
      for (let ox = 0; ox < 112; ox++) {
        const ix = Math.round(ai * ox + bi * oy + txi);
        const iy = Math.round(-bi * ox + ai * oy + tyi);
        if (ix < 0 || ix >= W || iy < 0 || iy >= H) continue;
        const si = (iy * W + ix) * C;
        const di = (oy * 112 + ox) * 3;
        out[di] = src[si]; out[di + 1] = src[si + 1]; out[di + 2] = src[si + 2];
      }
    }
    return out;
  }

  /** Fallback: simple crop + resize when keypoints are unavailable. */
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
   * Compute similarity transform (uniform scale + rotation + translation) from src → dst.
   * Returns [a, b, tx, ty] for: [dx,dy] = [[a,-b],[b,a]] * [sx,sy] + [tx,ty]
   * Uses least-squares over all N point pairs (Umeyama-style, rotation+scale only).
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
   * InsightFace models (SCRFD + ArcFace) expect BGR channel order.
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
   * Parse SCRFD outputs, returning the highest-scoring face with 5-point keypoints.
   * Bbox: distances [left, top, right, bottom] from anchor center, scaled by stride.
   * Kps:  offsets [Δx, Δy] × 5 from anchor center, scaled by stride.
   */
  private parseBestDetection(
    outputs: Record<string, ort.Tensor>,
    scaleX: number,
    scaleY: number,
  ): DetectedFace | null {
    let best: DetectedFace | null = null;

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
        const score = scores[i];
        if (score < this.SCORE_THRESH) continue;

        const anchorIdx = Math.floor(i / this.NUM_ANCHORS);
        const cx = ((anchorIdx % fW) + 0.5) * stride;
        const cy = (Math.floor(anchorIdx / fW) + 0.5) * stride;

        const x1 = (cx - boxes[i * 4]     * stride) * scaleX;
        const y1 = (cy - boxes[i * 4 + 1] * stride) * scaleY;
        const x2 = (cx + boxes[i * 4 + 2] * stride) * scaleX;
        const y2 = (cy + boxes[i * 4 + 3] * stride) * scaleY;

        const keypoints: [number, number][] = [];
        if (kps) {
          for (let j = 0; j < 5; j++) {
            keypoints.push([
              (cx + kps[i * 10 + j * 2]     * stride) * scaleX,
              (cy + kps[i * 10 + j * 2 + 1] * stride) * scaleY,
            ]);
          }
        }

        if (!best || score > best.score) {
          best = { box: [x1, y1, x2, y2], score, keypoints };
        }
      }
    }

    return best;
  }
}
