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
  workHoursStart?: number; // 0-23, default 9
  workHoursEnd?: number;   // 0-23, default 18
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

// Gen-z, sarcastic, funny tone. Max 1 sentence, 10-15 words. Slang welcome.
export const POOL_GENERATION_PROMPTS: Record<string, string> = {
  stand_up: 'Generate gen-z stand-up reminders. Sarcastic/funny. e.g., "Bestie your legs are literally decorative at this point." or "Stand up before you fuse with that chair fr."',
  hydration: 'Generate gen-z water reminders. Funny/sarcastic. e.g., "Hydrate or diedrate bestie." or "Your cells are literally begging rn. Drink water."',
  eye_break: 'Generate gen-z eye break reminders. e.g., "Your retinas are cooked. Look away for 20 sec." or "Screen break or we\'re gonna need glasses. Oh wait."',
  stretch: 'Generate gen-z stretch reminders. Roast their posture. e.g., "Your spine is not supposed to be shaped like a shrimp. Stretch." or "Roll those shoulders before they file a complaint."',
  posture: 'Generate gen-z posture nudges. Light roast energy. e.g., "Posture check — you\'re giving hunchback of Notre Dame rn." or "Sit up. You look like a deflated balloon."',
  welcome_back_short: 'Generate gen-z welcome-back greetings. Max 6 words. e.g., "Oh look who decided to return." or "The main character is back."',
  welcome_back_long: 'Generate gen-z welcome-back for long absences. Sarcastic. e.g., "Thought you uninstalled me ngl." or "Did you go touch grass? Respect."',
  pomodoro_break: 'Generate gen-z break messages. e.g., "Break time bestie, you ate that sesh." or "Touch grass for 5 min. You earned it."',
  pomodoro_focus: 'Generate gen-z focus-start messages. Hype energy. e.g., "Lock in. No cap we\'re cooking now." or "Focus mode activated. Let\'s eat."',
  error: 'Generate gen-z error messages. Self-deprecating. e.g., "Oop. I broke. This is embarrassing." or "Ngl something went wrong. My bad bestie."',
};
