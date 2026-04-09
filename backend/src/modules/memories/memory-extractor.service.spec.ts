import { MemoryExtractorService } from './memory-extractor.service';

describe('MemoryExtractorService', () => {
  let service: MemoryExtractorService;
  let mockLlm: { generate: jest.Mock };

  beforeEach(() => {
    mockLlm = {
      generate: jest.fn(),
    };
    service = new MemoryExtractorService(mockLlm as any);
  });

  it('returns empty array for empty transcript', async () => {
    const result = await service.extractFromTranscript([], []);
    expect(result).toEqual([]);
    expect(mockLlm.generate).not.toHaveBeenCalled();
  });

  it('extracts memories from LLM response', async () => {
    mockLlm.generate.mockResolvedValue({
      text: JSON.stringify([
        { fact: 'User is a developer', category: 'work' },
        { fact: 'User likes coffee', category: 'preference' },
      ]),
    });

    const result = await service.extractFromTranscript(
      [
        { role: 'user', content: 'I work as a developer and love coffee' },
        { role: 'assistant', content: 'Nice!' },
      ],
      [],
    );

    expect(result).toEqual([
      { fact: 'User is a developer', category: 'work' },
      { fact: 'User likes coffee', category: 'preference' },
    ]);
  });

  it('handles markdown code fences in response', async () => {
    mockLlm.generate.mockResolvedValue({
      text: '```json\n[{"fact": "Lives in Jakarta", "category": "location"}]\n```',
    });

    const result = await service.extractFromTranscript(
      [{ role: 'user', content: 'I live in Jakarta' }],
      [],
    );

    expect(result).toEqual([
      { fact: 'Lives in Jakarta', category: 'location' },
    ]);
  });

  it('filters out invalid categories', async () => {
    mockLlm.generate.mockResolvedValue({
      text: JSON.stringify([
        { fact: 'Valid fact', category: 'work' },
        { fact: 'Bad category', category: 'invalid_cat' },
      ]),
    });

    const result = await service.extractFromTranscript(
      [{ role: 'user', content: 'something' }],
      [],
    );

    expect(result).toHaveLength(1);
    expect(result[0].category).toBe('work');
  });

  it('filters out entries with empty facts', async () => {
    mockLlm.generate.mockResolvedValue({
      text: JSON.stringify([
        { fact: '', category: 'work' },
        { fact: 'Real fact', category: 'personal' },
      ]),
    });

    const result = await service.extractFromTranscript(
      [{ role: 'user', content: 'something' }],
      [],
    );

    expect(result).toHaveLength(1);
    expect(result[0].fact).toBe('Real fact');
  });

  it('returns empty array on LLM error', async () => {
    mockLlm.generate.mockRejectedValue(new Error('API error'));

    const result = await service.extractFromTranscript(
      [{ role: 'user', content: 'hello' }],
      [],
    );

    expect(result).toEqual([]);
  });

  it('returns empty array on unparseable response', async () => {
    mockLlm.generate.mockResolvedValue({ text: 'not json at all' });

    const result = await service.extractFromTranscript(
      [{ role: 'user', content: 'hello' }],
      [],
    );

    expect(result).toEqual([]);
  });

  it('returns empty array when LLM returns empty array', async () => {
    mockLlm.generate.mockResolvedValue({ text: '[]' });

    const result = await service.extractFromTranscript(
      [{ role: 'user', content: 'hello' }],
      [],
    );

    expect(result).toEqual([]);
  });

  it('passes existing memories to the prompt', async () => {
    mockLlm.generate.mockResolvedValue({ text: '[]' });

    await service.extractFromTranscript(
      [{ role: 'user', content: 'hello' }],
      [{ fact: 'User is named Hendra', category: 'personal' }],
    );

    const callArgs = mockLlm.generate.mock.calls[0];
    const userMessage = callArgs[1][0].content;
    expect(userMessage).toContain('User is named Hendra (personal)');
  });
});
