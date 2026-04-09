/**
 * Accumulates LLM streaming tokens and emits complete sentences.
 * Used between LLM stream and TTS — TTS needs complete sentences
 * for natural prosody.
 */
export class SentenceBuffer {
  private buffer = '';
  private readonly boundaries = /([.!?।。？！])\s+/;

  /**
   * Feed a token from the LLM stream.
   * Returns a complete sentence if a boundary was detected, null otherwise.
   */
  feed(token: string): string | null {
    this.buffer += token;

    const match = this.buffer.match(this.boundaries);
    if (match && match.index !== undefined) {
      const boundaryIndex = match.index + match[0].length;
      const sentence = this.buffer.slice(0, boundaryIndex).trim();
      this.buffer = this.buffer.slice(boundaryIndex);
      return sentence;
    }

    return null;
  }

  /** Flush remaining buffer (last sentence may not end with punctuation). */
  flush(): string | null {
    const remaining = this.buffer.trim();
    this.buffer = '';
    return remaining || null;
  }
}
