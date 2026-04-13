import { AiService } from './ai.service';
import { PromptService } from './prompt.service';
import type { PipelineEvent } from './ai.service';

describe('AiService', () => {
  let service: AiService;
  let mockStt: any;
  let mockLlm: any;
  let mockTts: any;
  let mockCodec: any;
  let promptService: PromptService;

  beforeEach(() => {
    mockStt = {
      createStream: jest.fn(),
    };

    mockLlm = {
      generateStream: jest.fn(),
    };

    mockTts = {
      synthesize: jest.fn().mockResolvedValue(Buffer.from('pcm-audio')),
    };

    mockCodec = {
      encode: jest.fn().mockReturnValue(Buffer.from('opus-audio')),
      decode: jest.fn().mockReturnValue(Buffer.from('pcm-decoded')),
    };

    promptService = new PromptService();

    service = new AiService(
      mockStt,
      mockLlm,
      mockTts,
      mockCodec,
      null, // no TTS cache in tests
      promptService,
    );
  });

  describe('createSttStream', () => {
    it('delegates to STT provider', () => {
      const mockStream = { on: jest.fn() };
      mockStt.createStream.mockReturnValue(mockStream);

      const result = service.createSttStream({ languages: ['en-US'] });
      expect(result).toBe(mockStream);
      expect(mockStt.createStream).toHaveBeenCalledWith({ languages: ['en-US'] });
    });
  });

  describe('decodeAudio', () => {
    it('delegates to codec', () => {
      const input = Buffer.from('opus');
      const result = service.decodeAudio(input);
      expect(mockCodec.decode).toHaveBeenCalledWith(input);
      expect(result).toEqual(Buffer.from('pcm-decoded'));
    });
  });

  describe('encodeAudio', () => {
    it('delegates to codec', () => {
      const input = Buffer.from('pcm');
      const result = service.encodeAudio(input);
      expect(mockCodec.encode).toHaveBeenCalledWith(input);
      expect(result).toEqual(Buffer.from('opus-audio'));
    });
  });

  describe('processTranscript', () => {
    async function collectEvents(
      gen: AsyncGenerator<PipelineEvent>,
    ): Promise<PipelineEvent[]> {
      const events: PipelineEvent[] = [];
      for await (const event of gen) {
        events.push(event);
      }
      return events;
    }

    it('streams text and audio events for a single sentence', async () => {
      // LLM yields tokens that form one sentence
      async function* fakeStream() {
        yield 'Hello ';
        yield 'world.';
      }
      mockLlm.generateStream.mockReturnValue(fakeStream());

      const events = await collectEvents(
        service.processTranscript('Hi', [], []),
      );

      // "Hello world." won't be emitted by feed() since there's no trailing space
      // It will be flushed at the end
      const textEvents = events.filter((e) => e.type === 'text');
      const audioEvents = events.filter((e) => e.type === 'audio');
      const doneEvents = events.filter((e) => e.type === 'done');

      expect(textEvents.length).toBeGreaterThanOrEqual(1);
      expect(audioEvents.length).toBe(textEvents.length);
      expect(doneEvents).toHaveLength(1);
      expect((doneEvents[0] as any).fullText).toBe('Hello world.');
    });

    it('streams multiple sentences', async () => {
      async function* fakeStream() {
        yield 'First sentence. ';
        yield 'Second sentence.';
      }
      mockLlm.generateStream.mockReturnValue(fakeStream());

      const events = await collectEvents(
        service.processTranscript('Tell me', [], []),
      );

      const textEvents = events.filter((e) => e.type === 'text');
      expect(textEvents.length).toBe(2);
      expect((textEvents[0] as any).text).toBe('First sentence.');
      expect((textEvents[1] as any).text).toBe('Second sentence.');
    });

    it('calls TTS for each sentence and encodes to Opus', async () => {
      async function* fakeStream() {
        yield 'Hello. ';
        yield 'World.';
      }
      mockLlm.generateStream.mockReturnValue(fakeStream());

      await collectEvents(
        service.processTranscript('Hi', [], []),
      );

      // 2 sentences = 2 TTS calls + 2 codec encode calls
      expect(mockTts.synthesize).toHaveBeenCalledTimes(2);
      expect(mockCodec.encode).toHaveBeenCalledTimes(2);
      // synthesize(text, voiceOptions, signal) — signal is undefined when no AbortController used
      expect(mockTts.synthesize).toHaveBeenCalledWith('Hello.', {}, undefined);
    });

    it('passes history and system prompt to LLM', async () => {
      async function* fakeStream() {
        yield 'Response.';
      }
      mockLlm.generateStream.mockReturnValue(fakeStream());

      const history = [{ role: 'user', content: 'Previous' }];
      await collectEvents(
        service.processTranscript('Current', [], history),
      );

      expect(mockLlm.generateStream).toHaveBeenCalledWith(
        expect.stringContaining('gen-z energy'),
        expect.arrayContaining([
          { role: 'user', content: 'Previous' },
          { role: 'user', content: 'Current' },
        ]),
      );
    });

    it('handles empty LLM response', async () => {
      async function* fakeStream() {
        // yields nothing
      }
      mockLlm.generateStream.mockReturnValue(fakeStream());

      const events = await collectEvents(
        service.processTranscript('Hi', [], []),
      );

      expect(events).toEqual([{ type: 'done', fullText: '', cacheKeys: [] }]);
      expect(mockTts.synthesize).not.toHaveBeenCalled();
    });
  });
});
