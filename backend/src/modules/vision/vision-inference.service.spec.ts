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

  it('toNchw should produce correct shape with BGR channel order', () => {
    // RGB pixel: R=100, G=150, B=200
    const buf = Buffer.alloc(4 * 3);
    for (let i = 0; i < 4; i++) { buf[i*3]=100; buf[i*3+1]=150; buf[i*3+2]=200; }
    const result = service.toNchw(buf, 2, 2);
    expect(result).toHaveLength(3 * 4); // 3 channels * 4 pixels
    // Channel 0 = B: (200 - 127.5) / 128 = 0.566...
    expect(result[0]).toBeCloseTo((200 - 127.5) / 128, 4);
    // Channel 1 = G: (150 - 127.5) / 128 = 0.175...
    expect(result[4]).toBeCloseTo((150 - 127.5) / 128, 4);
    // Channel 2 = R: (100 - 127.5) / 128 = -0.214...
    expect(result[8]).toBeCloseTo((100 - 127.5) / 128, 4);
  });

  it('l2Normalize should produce unit vector', () => {
    const v = new Float32Array([3, 4]);
    const normalized = service.l2Normalize(v);
    const norm = Math.sqrt(normalized[0] ** 2 + normalized[1] ** 2);
    expect(norm).toBeCloseTo(1.0, 5);
  });
});
