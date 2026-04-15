export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface LlmResponse {
  text: string;
  tokensUsed?: { prompt: number; completion: number };
}

export interface ILlmProvider {
  generate(systemPrompt: string, messages: ChatMessage[]): Promise<LlmResponse>;

  generateStream(
    systemPrompt: string,
    messages: ChatMessage[],
  ): AsyncGenerator<string>;
}
