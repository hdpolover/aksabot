import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  GoogleGenerativeAI,
  GenerativeModel,
  HarmCategory,
  HarmBlockThreshold,
} from '@google/generative-ai';
import type { ILlmProvider, ChatMessage, LlmResponse } from '../interfaces';

@Injectable()
export class GeminiLlmProvider implements ILlmProvider {
  private model: GenerativeModel;

  constructor(private readonly config: ConfigService) {
    const apiKey = config.get<string>('GEMINI_API_KEY');
    if (!apiKey) throw new Error('GEMINI_API_KEY is required');

    const genAI = new GoogleGenerativeAI(apiKey);
    this.model = genAI.getGenerativeModel({
      model: 'gemini-2.5-flash',
      safetySettings: [
        {
          category: HarmCategory.HARM_CATEGORY_HARASSMENT,
          threshold: HarmBlockThreshold.BLOCK_NONE,
        },
        {
          category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,
          threshold: HarmBlockThreshold.BLOCK_NONE,
        },
        {
          category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
          threshold: HarmBlockThreshold.BLOCK_NONE,
        },
        {
          category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
          threshold: HarmBlockThreshold.BLOCK_NONE,
        },
      ],
    });
  }

  async generate(
    systemPrompt: string,
    messages: ChatMessage[],
  ): Promise<LlmResponse> {
    const chat = this.model.startChat({
      systemInstruction: { role: 'user', parts: [{ text: systemPrompt }] },
      history: messages.slice(0, -1).map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      })),
    });

    const lastMessage = messages[messages.length - 1];
    const result = await chat.sendMessage(lastMessage.content);
    const usage = result.response.usageMetadata;

    return {
      text: result.response.text(),
      tokensUsed: usage
        ? {
            prompt: usage.promptTokenCount ?? 0,
            completion: usage.candidatesTokenCount ?? 0,
          }
        : undefined,
    };
  }

  async *generateStream(
    systemPrompt: string,
    messages: ChatMessage[],
  ): AsyncGenerator<string> {
    const chat = this.model.startChat({
      systemInstruction: { role: 'user', parts: [{ text: systemPrompt }] },
      history: messages.slice(0, -1).map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      })),
    });

    const lastMessage = messages[messages.length - 1];
    const result = await chat.sendMessageStream(lastMessage.content);

    for await (const chunk of result.stream) {
      const text = chunk.text();
      if (text) yield text;
    }
  }
}
