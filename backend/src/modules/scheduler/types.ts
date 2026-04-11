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
}

export const DEFAULT_REMINDER_CONFIG: ReminderConfig = {
  standUp: { enabled: true, intervalMinutes: 60 },
  hydration: { enabled: true, intervalMinutes: 45 },
  eyeBreak: { enabled: true, intervalMinutes: 20 },
  stretch: { enabled: true, intervalMinutes: 90 },
  posture: { enabled: true, intervalMinutes: 30 },
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
  stand_up: { expression: 'encouraging', screenMode: 'reminder', durationMs: 10_000 },
  hydration: { expression: 'cheerful', screenMode: 'reminder', durationMs: 8_000 },
  eye_break: { expression: 'calm', screenMode: 'countdown', countdownSeconds: 20 },
  stretch: { expression: 'encouraging', screenMode: 'reminder', durationMs: 10_000 },
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

// All prompts use casual, punchy tone — like a friend, not a wellness app.
// Each message should be 1 sentence, max 10-15 words. No exclamation spam.
export const POOL_GENERATION_PROMPTS: Record<string, string> = {
  stand_up: 'Generate casual stand-up reminders like a friend would say. Short, no lectures. e.g., "Yo, legs exist. Use them." or "Stand up, stretch it out."',
  hydration: 'Generate casual water reminders. Not preachy. e.g., "Drink some water, dude." or "Hydration check."',
  eye_break: 'Generate casual eye break reminders. e.g., "Eyes off screen. Look far away for 20 sec." or "20-20-20 time. Your eyes will thank you."',
  stretch: 'Generate casual stretch reminders mentioning shoulders, wrists, or neck. e.g., "Roll those shoulders real quick." or "Wrists feeling tight? Stretch em."',
  posture: 'Generate casual posture nudges. Not naggy. e.g., "Sit up straight, you gremlin." or "Posture check."',
  welcome_back_short: 'Generate quick welcome-back greetings. Max 6 words. e.g., "Oh hey, you\'re back." or "There you are."',
  welcome_back_long: 'Generate welcome-back messages for longer absences. Still casual. e.g., "Long meeting? Welcome back." or "Missed you. Kinda."',
  pomodoro_break: 'Generate casual break-time messages. e.g., "Break time. Step away for a sec." or "Nice focus sesh. Take five."',
  pomodoro_focus: 'Generate casual focus-start messages. e.g., "Alright, let\'s lock in." or "Focus mode. Let\'s go."',
  error: 'Generate casual error messages. e.g., "Something broke. My bad." or "Uh, that didn\'t work. Try again?"',
};
