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
  toNchw(buf: Buffer, width: number, height: number): Float32Array {
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
