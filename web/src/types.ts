// ── Expression enum (mirrors firmware face::Expression) ──

export enum Expression {
  IDLE = 0,
  LISTENING = 1,
  THINKING = 2,
  SPEAKING = 3,
  CONFUSED = 4,
  SLEEPING = 5,
  OFFLINE = 6,
  ENCOURAGING = 7,
  CALM = 8,
  FOCUSED = 9,
  HAPPY = 10,
  SAD = 11,
  COUNT = 12,
}

export const EXPRESSION_NAMES: Record<number, string> = {
  [Expression.IDLE]: '',
  [Expression.LISTENING]: 'Listening',
  [Expression.THINKING]: 'Thinking',
  [Expression.SPEAKING]: 'Speaking',
  [Expression.CONFUSED]: 'Hmm?',
  [Expression.SLEEPING]: 'Sleeping',
  [Expression.OFFLINE]: 'Offline',
  [Expression.ENCOURAGING]: 'Hey!',
  [Expression.CALM]: 'Relax',
  [Expression.FOCUSED]: 'Focus',
  [Expression.HAPPY]: 'Happy',
  [Expression.SAD]: 'Sad',
};

// ── Face state (mirrors firmware FaceState struct) ──

export interface FaceState {
  expression: Expression;

  // Blink
  eyesOpen: boolean;
  blinking: boolean;
  blinkScale: number; // 1.0 = open, 0.0 = closed

  // Mouth
  mouthAmp: number; // 0.0-1.0

  // Sleeping / breathing
  breathPhase: number; // 0.0-1.0 cycle

  // Thinking
  thinkDots: number; // 0-3

  // Pupil drift
  driftX: number;
  driftY: number;

  // Idle fidget
  fidgetX: number;
  fidgetY: number;

  // Listening pulse
  listenPhase: number;

  // Bounce
  bounceY: number;

  // Sad teardrop
  tearActive: boolean;
  tearY: number;
  tearSide: number; // -1 left, +1 right

  // Glow
  glowPhase: number;

  // Idle micro-animation
  leftEyeScale: number;
  rightEyeScale: number;
  yawnAmp: number;
  popScale: number;

  // Transition
  transitionActive: boolean;
  transitionProgress: number;
}

// ── Display modes (mirrors firmware display::Mode) ──

export enum DisplayMode {
  FACE = 0,
  CLOCK = 1,
  POMODORO = 2,
  REMINDER = 3,
  COUNTDOWN = 4,
  STATUS = 5,
}

// ── Color types ──

export interface RGB {
  r: number;
  g: number;
  b: number;
}

export interface Palette {
  bg: RGB;
  iris: RGB;
  irisRing: RGB;
  accent: RGB;
  mouth: RGB;
  label: RGB;
  sclera: RGB;
}

export interface EyeShape {
  r: number;
  pupilR: number;
  pupilOX: number;
  pupilOY: number;
  canBlink: boolean;
  hasBrows: boolean;
}

// ── Display data types ──

export interface StatusBar {
  wifiRssi: number;
  wifiConnected: boolean;
  wsConnected: boolean;
  batteryPercent: number; // 255 = USB
  focusModeActive: boolean;
  pomodoroActive: boolean;
  pomodoroCycle: number;
}

export interface PomodoroData {
  phaseLabel: string;
  remainingSeconds: number;
  currentCycle: number;
  totalCycles: number;
}

export interface ReminderData {
  text: string;
  icon: string;
  durationMs: number;
}

export interface CountdownData {
  remainingSeconds: number;
  instruction: string;
}

// ── Canvas dimensions (matches ESP32 TFT) ──

export const LCD_WIDTH = 240;
export const LCD_HEIGHT = 320;
export const CX = LCD_WIDTH / 2; // 120
export const CY = LCD_HEIGHT / 2 - 20; // 140
export const EYE_SPACE = 48;
export const MOUTH_Y = CY + 42; // 182
