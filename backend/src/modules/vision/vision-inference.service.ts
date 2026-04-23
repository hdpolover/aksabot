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
  private readonly SCORE_THRESH = 0.3;

  // buffalo_l det_10g.onnx output key mapping (numeric node names):
  // stride 8→[448=score, 451=bbox], stride 16→[471, 474], stride 32→[494, 497]
  private readonly SCORE_KEYS = ['448', '471', '494'];
  private readonly BBOX_KEYS  = ['451', '474', '497'];

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

    // Clamp box to image bounds — sharp throws if extract region extends outside image
    const meta = await sharp(jpegBuffer).metadata();
    const imgW = meta.width ?? this.DET_SIZE;
    const imgH = meta.height ?? this.DET_SIZE;

    const left   = Math.max(0, Math.round(box[0]));
    const top    = Math.max(0, Math.round(box[1]));
    const right  = Math.min(imgW, Math.round(box[2]));
    const bottom = Math.min(imgH, Math.round(box[3]));
    const width  = Math.max(1, right - left);
    const height = Math.max(1, bottom - top);

    const { data } = await sharp(jpegBuffer)
      .extract({ left, top, width, height })
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

  /**
   * Convert interleaved RGB Buffer to BGR NCHW Float32Array.
   * InsightFace models (SCRFD + ArcFace) expect BGR channel order, same mean/std.
   */
  toNchw(buf: Buffer, width: number, height: number): Float32Array {
    const pixels = width * height;
    const nchw = new Float32Array(3 * pixels);
    for (let i = 0; i < pixels; i++) {
      const r = buf[i * 3], g = buf[i * 3 + 1], b = buf[i * 3 + 2];
      nchw[i]             = (b - 127.5) / 128; // channel 0 = B
      nchw[pixels + i]    = (g - 127.5) / 128; // channel 1 = G
      nchw[2 * pixels + i]= (r - 127.5) / 128; // channel 2 = R
    }
    return nchw;
  }

  /** L2-normalize a Float32Array to unit length. */
  l2Normalize(embedding: Float32Array): number[] {
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

    for (let si = 0; si < this.STRIDES.length; si++) {
      const stride = this.STRIDES[si];
      const fH = Math.ceil(this.DET_SIZE / stride);
      const fW = Math.ceil(this.DET_SIZE / stride);
      const totalAnchors = fH * fW * this.NUM_ANCHORS;

      const scores = outputs[this.SCORE_KEYS[si]]?.data as Float32Array | undefined;
      const boxes = outputs[this.BBOX_KEYS[si]]?.data as Float32Array | undefined;
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
