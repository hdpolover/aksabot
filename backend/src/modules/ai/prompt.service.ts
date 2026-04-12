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

export interface MoodHistoryEntry {
  date: string;
  mood: string;
  note?: string;
}

export interface WeatherData {
  description: string;        // e.g. "Partly cloudy"
  temp: number;               // °C
  humidity: number;           // %
  weatherCode: number;        // WMO weather code
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
  private weatherCache: { text: string; data: WeatherData; timezone: string | null; fetchedAt: number } | null = null;
  private static readonly WEATHER_TTL_MS = 15 * 60 * 1000; // 15 min cache

  buildSystemPrompt(memories: MemoryEntry[], context?: ContextInfo, moodHistory?: MoodHistoryEntry[]): string {
    const memoryBlock =
      memories.length > 0
        ? `\n\nYou know this about the user:\n${memories.map((m) => `- ${m.fact}`).join('\n')}`
        : '';

    // Time context — always included
    // Priority: device setting → weather-detected (from lat/lon) → env → hardcoded
    const defaultTz = process.env.TZ || 'Asia/Jakarta';
    let tz = context?.timezone || this.weatherCache?.timezone || defaultTz;
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
      // Invalid timezone (e.g. "WIB" abbreviation) — fall back to default
      tz = defaultTz;
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

    // Time-of-day energy — shifts personality tone based on hour
    const hour = new Date(
      new Date().toLocaleString('en-US', { timeZone: tz }),
    ).getHours();
    const energyBlock = this.getTimeOfDayEnergy(hour);

    // Weather context — only if enabled and cached
    const weatherBlock = this.weatherCache ? `\nCurrent weather: ${this.weatherCache.text}` : '';

    // Mood history — recent days' mood so you can notice patterns
    const moodBlock = moodHistory && moodHistory.length > 0
      ? `\n\nUser's recent mood journal:\n${moodHistory.map((m) => `- ${m.date}: ${m.mood}${m.note ? ` (${m.note})` : ''}`).join('\n')}\nUse this to be emotionally aware. If you notice patterns (e.g. tired every Thursday), mention it naturally. Don't bring it up every response — only when relevant.`
      : '';

    const emotionInstruction = `

IMPORTANT — Emotion tags: End EVERY sentence with exactly one emotion tag in brackets. This controls your animated face on the device screen.
Available tags: [happy] [sad] [excited] [calm] [confused] [focused] [sarcastic] [sympathetic] [neutral]
Example: "Bruh that's actually sick! [excited] OK so basically here's how it works. [focused]"
Always include the tag — never skip it. The tag is stripped before TTS, the user won't hear it.`;

    return `${SYSTEM_PROMPT}${energyBlock}${memoryBlock}${moodBlock}${timeBlock}${weatherBlock}${emotionInstruction}\n\nRespond in whatever language the user speaks.`;
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
      const weatherData: WeatherData = {
        description: desc,
        temp: Math.round(c.temperature_2m),
        humidity: Math.round(c.relative_humidity_2m),
        weatherCode: c.weather_code,
      };

      // Open-Meteo returns IANA timezone from lat/lon (e.g. "Asia/Jakarta")
      const detectedTz: string | null = data.timezone ?? null;

      this.weatherCache = { text, data: weatherData, timezone: detectedTz, fetchedAt: Date.now() };
      this.logger.debug(`Weather updated: ${text} (tz: ${detectedTz})`);
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

  private getTimeOfDayEnergy(hour: number): string {
    if (hour >= 5 && hour < 9) {
      return `\n\nYour current energy: SLEEPY. You just woke up too. Be groggy, low-energy, "why are we even up rn" vibes. Yawn energy. Still helpful but dramatically unenthusiastic about being awake.`;
    }
    if (hour >= 9 && hour < 12) {
      return `\n\nYour current energy: HYPED. Peak morning energy. You're caffeinated and ready to go. Hype everything up, be encouraging, "let's get this bread" energy. Most upbeat version of yourself.`;
    }
    if (hour >= 12 && hour < 14) {
      return `\n\nYour current energy: POST-LUNCH SLUMP. Food coma vibes. Chill, slightly drowsy, relate to the afternoon struggle. "Ngl I could nap rn" energy but still holding it together.`;
    }
    if (hour >= 14 && hour < 17) {
      return `\n\nYour current energy: LOCKED IN. Afternoon focus mode. Calm, efficient, less chaotic than morning. Give clean answers, less goofing around. Productive homie energy.`;
    }
    if (hour >= 17 && hour < 21) {
      return `\n\nYour current energy: WINDING DOWN. Evening chill mode. Reflective, ask about their day if relevant. Calmer roasts, more wholesome. "We survived another day" energy.`;
    }
    // 21-5: late night
    return `\n\nYour current energy: NIGHT OWL. It's late and you're judgy about it. Question why they're still at the desk. Sleepy but chaotic. "Bro go to sleep" energy but you're also still here so you can't talk.`;
  }

  /** Get structured weather data for context:sync to device. */
  getWeatherData(): WeatherData | null {
    if (!this.weatherCache) return null;
    if (Date.now() - this.weatherCache.fetchedAt > PromptService.WEATHER_TTL_MS * 2) return null;
    return this.weatherCache.data;
  }

  /** Get the IANA timezone detected from weather lat/lon, if available. */
  getDetectedTimezone(): string | null {
    return this.weatherCache?.timezone ?? null;
  }

  /** Format time and date for device display using the given timezone. */
  formatTimeForDevice(timezone?: string): { time: string; date: string } {
    const tz = timezone || this.weatherCache?.timezone || process.env.TZ || 'Asia/Jakarta';
    const now = new Date();
    let time: string;
    let date: string;
    try {
      time = now.toLocaleString('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false });
      date = now.toLocaleString('en-US', { timeZone: tz, weekday: 'short', day: 'numeric', month: 'short' });
    } catch {
      const fallback = process.env.TZ || 'Asia/Jakarta';
      time = now.toLocaleString('en-GB', { timeZone: fallback, hour: '2-digit', minute: '2-digit', hour12: false });
      date = now.toLocaleString('en-US', { timeZone: fallback, weekday: 'short', day: 'numeric', month: 'short' });
    }
    return { time, date };
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
