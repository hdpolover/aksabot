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
