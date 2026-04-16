import { create } from 'zustand';
import { Expression, DisplayMode } from '../types';

export interface ProactiveData {
  type: 'reminder' | 'nudge' | 'briefing' | 'pomodoro';
  text: string;
  icon?: string;
  durationMs: number;
  pomodoroPhase?: string;
  pomodoroRemaining?: number;
  pomodoroCycle?: number;
  pomodoroTotalCycles?: number;
}

interface FaceState {
  expression: Expression;
  displayMode: DisplayMode;
  proactive: ProactiveData | null;

  setExpression: (expr: Expression) => void;
  setMode: (mode: DisplayMode) => void;
  showProactive: (data: ProactiveData) => void;
  dismissProactive: () => void;
}

export const useFaceStore = create<FaceState>((set) => ({
  expression: Expression.OFFLINE,
  displayMode: DisplayMode.FACE,
  proactive: null,

  setExpression(expr) {
    set({ expression: expr });
  },

  setMode(mode) {
    set({ displayMode: mode });
  },

  showProactive(data) {
    set({ proactive: data });
  },

  dismissProactive() {
    set({ proactive: null });
  },
}));
