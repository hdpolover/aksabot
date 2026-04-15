export type ReminderType =
  | 'stand_up'
  | 'hydration'
  | 'eye_break'
  | 'stretch'
  | 'posture';

export interface ReminderConfig {
  standUp: { enabled: boolean; intervalMinutes: number };
  hydration: { enabled: boolean; intervalMinutes: number };
  eyeBreak: { enabled: boolean; intervalMinutes: number };
  stretch: { enabled: boolean; intervalMinutes: number };
  posture: { enabled: boolean; intervalMinutes: number };
  allDay: boolean; // true = run 24/7, false = restrict to work hours
  workHoursStart: number; // 0-23, default 9
  workHoursEnd: number; // 0-23, default 18
}

export const DEFAULT_REMINDER_CONFIG: ReminderConfig = {
  standUp: { enabled: true, intervalMinutes: 60 },
  hydration: { enabled: true, intervalMinutes: 45 },
  eyeBreak: { enabled: true, intervalMinutes: 20 },
  stretch: { enabled: true, intervalMinutes: 90 },
  posture: { enabled: true, intervalMinutes: 30 },
  allDay: false,
  workHoursStart: 9,
  workHoursEnd: 18,
};

export interface ReminderDisplayConfig {
  expression: string;
  screenMode: 'reminder' | 'countdown';
  durationMs?: number;
  countdownSeconds?: number;
}

export interface ReminderPayload {
  type: ReminderType | 'pomodoro_break' | 'pomodoro_focus';
  text: string;
  audio: Buffer;
  cacheKey: string | null;
  display: ReminderDisplayConfig;
}

export const REMINDER_DISPLAY: Record<ReminderType, ReminderDisplayConfig> = {
  stand_up: {
    expression: 'encouraging',
    screenMode: 'reminder',
    durationMs: 10_000,
  },
  hydration: {
    expression: 'cheerful',
    screenMode: 'reminder',
    durationMs: 8_000,
  },
  eye_break: {
    expression: 'calm',
    screenMode: 'countdown',
    countdownSeconds: 20,
  },
  stretch: {
    expression: 'encouraging',
    screenMode: 'reminder',
    durationMs: 10_000,
  },
  posture: { expression: 'gentle', screenMode: 'reminder', durationMs: 5_000 },
};

export interface PomodoroState {
  cycle: number;
  phase: 'focus' | 'short_break' | 'long_break';
  startedAt: Date;
  phaseStartedAt: Date;
  focusMinutes: number;
  shortBreakMinutes: number;
  longBreakMinutes: number;
  cyclesBeforeLongBreak: number;
  timer: ReturnType<typeof setTimeout> | null;
}

export const POOL_TARGET_SIZES: Record<string, number> = {
  stand_up: 15,
  hydration: 15,
  eye_break: 10,
  stretch: 10,
  posture: 10,
  welcome_back_short: 10,
  welcome_back_long: 10,
  pomodoro_break: 8,
  pomodoro_focus: 8,
  error: 5,
};

// Aksa's voice: gen-z, sarcastic, casually curses, best friend energy, no text abbreviations.
// Max 1 sentence, 10-15 words. These are spoken aloud via TTS — spell everything out.
export const POOL_GENERATION_PROMPTS: Record<string, string> = {
  stand_up:
    'Generate stand-up reminders in Aksa\'s voice — sarcastic best friend, can curse casually. e.g., "Your legs are literally decorative at this point, get up." or "Stand up before you fuse with that chair, man."',
  hydration:
    'Generate water reminders in Aksa\'s voice — funny, sarcastic. e.g., "You\'re literally going to shrivel up, drink some water." or "Your cells are begging. Drink water, come on."',
  eye_break:
    'Generate eye break reminders in Aksa\'s voice — direct, can be sarcastic. e.g., "Your retinas are cooked, look away for 20 seconds." or "Screen break or you\'re going to go blind. I\'m serious."',
  stretch:
    'Generate stretch reminders in Aksa\'s voice — roast the posture, best friend energy. e.g., "Your spine is not supposed to curve like that, stretch." or "Roll those shoulders before they file a damn complaint."',
  posture:
    'Generate posture nudges in Aksa\'s voice — light roast. e.g., "Posture check — you look like a sad shrimp right now." or "Sit up straight, you\'re not a question mark."',
  welcome_back_short:
    'Generate short welcome-back greetings in Aksa\'s voice. Max 6 words. e.g., "Oh look who decided to return." or "The man himself is back."',
  welcome_back_long:
    'Generate welcome-back for long absences in Aksa\'s voice. Sarcastic. e.g., "Thought you finally got rid of me, huh." or "Did you go touch grass? Respect honestly."',
  pomodoro_break:
    'Generate pomodoro break messages in Aksa\'s voice — celebratory, casual. e.g., "Break time, you actually crushed that session." or "Touch some grass for 5 minutes, you earned it."',
  pomodoro_focus:
    'Generate focus-start messages in Aksa\'s voice — hype energy, no cringe. e.g., "Lock in, we\'re actually cooking now." or "Focus mode, let\'s get this done."',
  error:
    'Generate error messages in Aksa\'s voice — self-deprecating, a little embarrassed. e.g., "Something broke, that\'s on me, give me a sec." or "Okay I messed up, this is embarrassing."',
};
