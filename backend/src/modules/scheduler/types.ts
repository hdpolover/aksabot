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

export const POOL_GENERATION_PROMPTS: Record<string, string> = {
  stand_up: 'Generate stand-up reminders for someone who has been sitting at their desk coding.',
  hydration: 'Generate water/hydration reminders. Brief and friendly.',
  eye_break: 'Generate 20-20-20 eye break reminders (look 20ft away for 20 seconds).',
  stretch: 'Generate stretch reminders, mention shoulders, wrists, or neck.',
  posture: 'Generate posture check nudges. Gentle, not preachy.',
  welcome_back_short: 'Generate short welcome-back greetings for when someone returns to their desk.',
  welcome_back_long: 'Generate welcome-back messages that mention the person was away for a while.',
  pomodoro_break: 'Generate messages for starting a pomodoro break after a focus session.',
  pomodoro_focus: 'Generate messages for starting a new pomodoro focus session after a break.',
  error: 'Generate friendly error messages for when something went wrong.',
};
