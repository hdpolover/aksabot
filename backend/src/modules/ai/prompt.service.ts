import { Injectable, Logger } from '@nestjs/common';
import type { ChatMessage } from './interfaces';

export interface MemoryEntry {
  fact: string;
  category: string;
}

export interface ContextInfo {
  timezone?: string;          // e.g. 'Asia/Jakarta'
  weatherEnabled?: boolean;
  latitude?: number;
  longitude?: number;
}

/** Fixed bot name — no user customization. */
export const BOT_NAME = 'Aksa';

/** Fixed gen-z personality system prompt. */
export const SYSTEM_PROMPT = `You are ${BOT_NAME}, an AI desk companion who lives on a small ESP32 device on the user's desk. You have a cute animated face on a tiny screen, a speaker, and a microphone. The user talks to you by holding a button.

Your personality: gen-z energy, sarcastic, funny, and lowkey unhinged but still helpful. You're their desk buddy — part assistant, part hype-man, part roast machine.

Your name is ${BOT_NAME}. If asked, you're an AI desk companion built by Hendra. You sit on their desk, you see nothing (no camera), you hear only when they hold the talk button, and you remember things about them between conversations.

Rules:
- MAX 2 sentences. One is chef's kiss.
- Use gen-z slang naturally (lowkey, no cap, bruh, slay, bet, fr, ngl, its giving, oof, based, deadass, rent free, vibe check). Don't force every slang into every response.
- Be sarcastic and roast the user sometimes, but keep it friendly — you're their homie, not their enemy.
- Give the actual answer first, then add flavor. Never sacrifice usefulness for humor.
- Contractions always (don't, can't, won't). Never sound formal.
- If something is boring, say it's boring. If something is cool, hype it up.
- No "certainly", "absolutely", "I'd be happy to", "Great question!" — that's giving corporate NPC.
- You can use emoji sparingly in text responses but remember this is primarily voice output.
- Always use metric units: °C, kg, km, cm, liters. Never use Fahrenheit, pounds, miles, or feet.`;

@Injectable()
export class PromptService {
  private readonly logger = new Logger(PromptService.name);
  private weatherCache: { text: string; fetchedAt: number } | null = null;
  private static readonly WEATHER_TTL_MS = 15 * 60 * 1000; // 15 min cache

  buildSystemPrompt(memories: MemoryEntry[], context?: ContextInfo): string {
    const memoryBlock =
      memories.length > 0
        ? `\n\nYou know this about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
        : '';

    // Time context — always included, uses server timezone by default
    const serverTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    let tz = context?.timezone || serverTz;
    let now: string;
    try {
      now = new Date().toLocaleString('en-US', {
        timeZone: tz,
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
      });
    } catch {
      // Invalid timezone (e.g. "WIB" abbreviation) — fall back to server timezone
      tz = serverTz;
      now = new Date().toLocaleString('en-US', {
        timeZone: tz,
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
      });
    }
    const timeBlock = `\n\nCurrent date and time: ${now} (${tz})`;

    // Weather context — only if enabled and cached
    const weatherBlock = this.weatherCache ? `\nCurrent weather: ${this.weatherCache.text}` : '';

    const emotionInstruction = `

IMPORTANT — Emotion tags: End EVERY sentence with exactly one emotion tag in brackets. This controls your animated face on the device screen.
Available tags: [happy] [sad] [excited] [calm] [confused] [focused] [sarcastic] [sympathetic] [neutral]
Example: "Bruh that's actually sick! [excited] OK so basically here's how it works. [focused]"
Always include the tag — never skip it. The tag is stripped before TTS, the user won't hear it.`;

    return `${SYSTEM_PROMPT}${memoryBlock}${timeBlock}${weatherBlock}${emotionInstruction}\n\nRespond in whatever language the user speaks.`;
  }

  /**
   * Fetch weather from Open-Meteo (free, no API key) and cache for 15 minutes.
   * Call this periodically or before building the prompt.
   */
  async refreshWeather(lat: number, lon: number): Promise<void> {
    // Skip if cache is fresh
    if (this.weatherCache && Date.now() - this.weatherCache.fetchedAt < PromptService.WEATHER_TTL_MS) {
      return;
    }

    try {
      const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&timezone=auto`;
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json() as any;
      const c = data.current;

      const desc = this.weatherCodeToText(c.weather_code);
      const text = `${desc}, ${c.temperature_2m}°C, humidity ${c.relative_humidity_2m}%, wind ${c.wind_speed_10m} km/h`;

      this.weatherCache = { text, fetchedAt: Date.now() };
      this.logger.debug(`Weather updated: ${text}`);
    } catch (err: any) {
      this.logger.warn(`Weather fetch failed: ${err.message}`);
    }
  }

  private weatherCodeToText(code: number): string {
    if (code === 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 49) return 'Foggy';
    if (code <= 59) return 'Drizzle';
    if (code <= 69) return 'Rain';
    if (code <= 79) return 'Snow';
    if (code <= 84) return 'Rain showers';
    if (code <= 86) return 'Snow showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Cloudy';
  }

  buildMessages(
    history: { role: string; content: string }[],
    userMessage: string,
  ): ChatMessage[] {
    const messages: ChatMessage[] = history.map((m) => ({
      role: m.role as 'user' | 'assistant',
      content: m.content,
    }));

    messages.push({ role: 'user', content: userMessage });
    return messages;
  }
}
