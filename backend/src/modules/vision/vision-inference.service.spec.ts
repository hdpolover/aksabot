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
    const result = service.toNchw(buf, 2, 2);
    expect(result).toHaveLength(3 * 4); // 3 channels * 4 pixels
    // Normalized: (100 - 127.5) / 128 = -0.21484375
    expect(result[0]).toBeCloseTo(-0.215, 2);
  });

  it('l2Normalize should produce unit vector', () => {
    const v = new Float32Array([3, 4]);
    const normalized = service.l2Normalize(v);
    const norm = Math.sqrt(normalized[0] ** 2 + normalized[1] ** 2);
    expect(norm).toBeCloseTo(1.0, 5);
  });
});
