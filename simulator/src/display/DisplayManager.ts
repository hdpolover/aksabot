import {
  DisplayMode,
  type StatusBar,
  type PomodoroData,
  type ReminderData,
  type CountdownData,
} from '../types';
import { FaceAnimator } from '../face/FaceAnimator';
import { renderFace } from './FaceRenderer';
import {
  renderClock,
  renderPomodoro,
  renderReminder,
  renderCountdown,
  renderStatus,
  renderTranscriptOverlay,
} from './ModeRenderers';

export class DisplayManager {
  readonly face: FaceAnimator;
  private ctx: CanvasRenderingContext2D;

  private currentMode = DisplayMode.FACE;
  private previousMode = DisplayMode.FACE;

  private autoReturnActive = false;
  private autoReturnAtMs = 0;

  private transcriptEnabled = false;
  private transcriptSpeaker = '';
  private transcriptText = '';

  statusBar: StatusBar = {
    wifiRssi: -50,
    wifiConnected: true,
    wsConnected: false,
    batteryPercent: 255,
    focusModeActive: false,
    pomodoroActive: false,
    pomodoroCycle: 0,
  };

  private pomodoroData: PomodoroData = {
    phaseLabel: 'FOCUS',
    remainingSeconds: 1500,
    currentCycle: 1,
    totalCycles: 4,
  };

  private reminderData: ReminderData = {
    text: '',
    icon: '',
    durationMs: 5000,
  };

  private countdownData: CountdownData = {
    remainingSeconds: 20,
    instruction: '',
  };

  constructor(ctx: CanvasRenderingContext2D) {
    this.ctx = ctx;
    this.face = new FaceAnimator();
  }

  init(nowMs: number): void {
    this.face.init(nowMs);
    this.currentMode = DisplayMode.FACE;
  }

  tick(nowMs: number): void {
    // Advance face animation
    this.face.tick(nowMs);

    // Check auto-return timer
    if (this.autoReturnActive && nowMs >= this.autoReturnAtMs) {
      this.autoReturnActive = false;
      this.currentMode = this.previousMode;
    }

    // Render current mode
    switch (this.currentMode) {
      case DisplayMode.FACE:
        renderFace(this.ctx, this.face.getState(), this.statusBar);
        break;
      case DisplayMode.CLOCK:
        renderClock(this.ctx, this.statusBar);
        break;
      case DisplayMode.POMODORO:
        renderPomodoro(this.ctx, this.pomodoroData);
        break;
      case DisplayMode.REMINDER:
        renderReminder(this.ctx, this.reminderData);
        break;
      case DisplayMode.COUNTDOWN:
        renderCountdown(this.ctx, this.countdownData);
        break;
      case DisplayMode.STATUS:
        renderStatus(this.ctx, this.statusBar);
        break;
    }

    // Transcript overlay
    if (this.transcriptEnabled && this.transcriptText) {
      renderTranscriptOverlay(this.ctx, this.transcriptSpeaker, this.transcriptText);
    }
  }

  setMode(mode: DisplayMode): void {
    if (mode === this.currentMode && !this.autoReturnActive) return;
    this.previousMode = this.currentMode;
    this.currentMode = mode;
    this.autoReturnActive = false;
  }

  getMode(): DisplayMode {
    return this.currentMode;
  }

  setModeTemporary(mode: DisplayMode, durationMs: number): void {
    this.previousMode = this.currentMode;
    this.currentMode = mode;
    this.autoReturnActive = true;
    this.autoReturnAtMs = performance.now() + durationMs;
  }

  showPomodoro(data: PomodoroData): void {
    this.pomodoroData = data;
    this.setMode(DisplayMode.POMODORO);
  }

  showReminder(data: ReminderData): void {
    this.reminderData = data;
    this.setModeTemporary(DisplayMode.REMINDER, data.durationMs > 0 ? data.durationMs : 5000);
  }

  showCountdown(data: CountdownData): void {
    this.countdownData = data;
    this.setMode(DisplayMode.COUNTDOWN);
  }

  setTranscriptOverlay(enabled: boolean): void {
    this.transcriptEnabled = enabled;
  }

  setTranscriptText(speaker: string, text: string): void {
    this.transcriptSpeaker = speaker;
    this.transcriptText = text;
  }
}
