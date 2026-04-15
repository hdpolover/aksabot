import { SentenceBuffer } from './sentence-buffer';

describe('SentenceBuffer', () => {
  let buffer: SentenceBuffer;

  beforeEach(() => {
    buffer = new SentenceBuffer();
  });

  it('returns null when no sentence boundary is found', () => {
    expect(buffer.feed('Hello')).toBeNull();
    expect(buffer.feed(' world')).toBeNull();
  });

  it('emits a sentence on period + space', () => {
    buffer.feed('Hello world');
    const result = buffer.feed('. Next');
    expect(result).toBe('Hello world.');
  });

  it('emits a sentence on exclamation + space', () => {
    buffer.feed('Wow');
    const result = buffer.feed('! That');
    expect(result).toBe('Wow!');
  });

  it('emits a sentence on question mark + space', () => {
    buffer.feed('How are you');
    const result = buffer.feed('? I am');
    expect(result).toBe('How are you?');
  });

  it('keeps remainder in buffer after emitting', () => {
    buffer.feed('First. ');
    // "First." was emitted, now feed more
    const second = buffer.feed('Second. Third');
    expect(second).toBe('Second.');
    expect(buffer.flush()).toBe('Third');
  });

  it('handles multiple sentences across many tokens', () => {
    expect(buffer.feed('A')).toBeNull();
    expect(buffer.feed('.')).toBeNull();
    expect(buffer.feed(' ')).toBe('A.');
    expect(buffer.feed('B! ')).toBe('B!');
    expect(buffer.flush()).toBeNull();
  });

  it('flush returns remaining text', () => {
    buffer.feed('Incomplete sentence');
    expect(buffer.flush()).toBe('Incomplete sentence');
  });

  it('flush returns null when buffer is empty', () => {
    expect(buffer.flush()).toBeNull();
  });

  it('flush returns null after whitespace-only content', () => {
    buffer.feed('   ');
    expect(buffer.flush()).toBeNull();
  });

  it('handles CJK sentence boundaries', () => {
    buffer.feed('你好。');
    const result = buffer.feed(' 下');
    expect(result).toBe('你好。');
  });

  it('does not split on period without trailing space', () => {
    buffer.feed('v2.0 is great');
    expect(buffer.flush()).toBe('v2.0 is great');
  });

  it('handles token-by-token streaming', () => {
    const tokens = [
      'I',
      ' am',
      ' fine',
      '.',
      ' How',
      ' are',
      ' you',
      '?',
      ' Good',
    ];
    const sentences: string[] = [];
    for (const t of tokens) {
      const result = buffer.feed(t);
      if (result) sentences.push(result);
    }
    sentences.push(buffer.flush()!);
    expect(sentences).toEqual(['I am fine.', 'How are you?', 'Good']);
  });
});
