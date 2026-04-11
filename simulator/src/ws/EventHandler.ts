import { Expression, DisplayMode } from '../types';
import type { DisplayManager } from '../display/DisplayManager';
import type { AudioPlayer } from './AudioPlayer';

const EXPR_MAP: Record<string, Expression> = {
  idle: Expression.IDLE,
  listening: Expression.LISTENING,
  thinking: Expression.THINKING,
  speaking: Expression.SPEAKING,
  confused: Expression.CONFUSED,
  sleeping: Expression.SLEEPING,
  offline: Expression.OFFLINE,
  encouraging: Expression.ENCOURAGING,
  calm: Expression.CALM,
  focused: Expression.FOCUSED,
  happy: Expression.HAPPY,
  sad: Expression.SAD,
};

const STATE_TO_EXPR: Record<string, Expression> = {
  idle: Expression.IDLE,
  listening: Expression.LISTENING,
  thinking: Expression.THINKING,
  speaking: Expression.SPEAKING,
  offline: Expression.OFFLINE,
  sleeping: Expression.SLEEPING,
};

export class EventHandler {
  private display: DisplayManager;
  private audioPlayer: AudioPlayer;
  private revertTimer: ReturnType<typeof setTimeout> | null = null;
  private onLog: (msg: string) => void;

  // Accumulate streamed response text so sentences don't replace each other
  private responseText = '';
  private transcriptHideTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(display: DisplayManager, audioPlayer: AudioPlayer, onLog: (msg: string) => void) {
    this.display = display;
    this.audioPlayer = audioPlayer;
    this.onLog = onLog;
  }

  handle(event: string, data: Record<string, unknown>): void {
    this.onLog(`${event}: ${JSON.stringify(data).slice(0, 80)}`);

    switch (event) {
      case 'state:update': {
        // Ignore state:update while audio is still playing — the backend sends
        // state:idle when it finishes sending frames, but we're still playing them.
        if (this.audioPlayer.isPlaying()) break;
        const state = data.state as string;
        const expr = STATE_TO_EXPR[state];
        if (expr !== undefined) {
          this.display.face.setExpression(expr);
        }
        break;
      }

      case 'face:expression': {
        const exprName = (data.expression as string)?.toLowerCase();
        const expr = EXPR_MAP[exprName];
        if (expr !== undefined) {
          this.display.face.setExpression(expr);
          const durationMs = data.durationMs as number | undefined;
          if (durationMs && durationMs > 0) {
            this.scheduleFaceRevert(durationMs);
          }
        }
        break;
      }

      case 'response:start':
        this.responseText = '';
        this.display.face.setExpression(Expression.SPEAKING);
        this.display.setTranscriptOverlay(true);
        if (this.transcriptHideTimer) {
          clearTimeout(this.transcriptHideTimer);
          this.transcriptHideTimer = null;
        }
        // Start audio playback — pass callback for when audio ACTUALLY finishes
        this.audioPlayer.startPlayback(() => {
          this.onPlaybackFinished();
        });
        break;

      case 'response:text': {
        // Backend streams one sentence per event — accumulate them
        const text = data.text as string ?? '';
        if (this.responseText) {
          this.responseText += ' ' + text;
        } else {
          this.responseText = text;
        }
        this.display.setTranscriptText('Bot', this.responseText);
        break;
      }

      case 'response:end':
        // Backend is done SENDING audio frames, but the browser may still be PLAYING them.
        // Don't revert to idle here — let the AudioPlayer's onEnd callback handle it.
        this.audioPlayer.markSendingDone();
        break;

      case 'transcript:partial': {
        const text = data.text as string ?? '';
        this.display.setTranscriptOverlay(true);
        this.display.setTranscriptText('You', text + '...');
        break;
      }

      case 'transcript:final': {
        const text = data.text as string ?? '';
        this.display.setTranscriptOverlay(true);
        this.display.setTranscriptText('You', text);
        break;
      }

      case 'proactive:reminder':
      case 'proactive:nudge':
      case 'proactive:briefing': {
        const displayData = data.display as Record<string, unknown> | undefined;
        if (displayData?.expression) {
          const expr = EXPR_MAP[(displayData.expression as string).toLowerCase()];
          if (expr !== undefined) this.display.face.setExpression(expr);
        }
        const text = data.text as string ?? 'Reminder';
        this.display.showReminder({
          text,
          icon: '!',
          durationMs: (displayData?.durationMs as number) ?? 5000,
        });
        break;
      }

      case 'proactive:pomodoro': {
        const action = data.action as string;
        if (action === 'stop') {
          this.display.face.setExpression(Expression.IDLE);
          this.display.setMode(DisplayMode.FACE);
        } else {
          const phase = data.phase as string ?? 'focus';
          const isFocus = phase === 'focus' || phase === 'work';
          this.display.face.setExpression(isFocus ? Expression.FOCUSED : Expression.CALM);
          this.display.showPomodoro({
            phaseLabel: phase,
            remainingSeconds: Math.round(((data.durationMs as number) ?? 1500000) / 1000),
            currentCycle: (data.cycle as number) ?? 1,
            totalCycles: 4,
          });
        }
        break;
      }

      case 'focus:start':
        this.display.face.setExpression(Expression.FOCUSED);
        break;

      case 'focus:end':
        this.display.face.setExpression(Expression.IDLE);
        break;

      case 'error':
        this.display.face.setExpression(Expression.CONFUSED);
        this.scheduleFaceRevert(2500);
        break;

      case 'session:start':
      case 'session:end':
        break;
    }
  }

  /** Called by AudioPlayer when all queued audio has actually finished playing */
  private onPlaybackFinished(): void {
    this.onLog('Audio playback finished');
    this.display.face.setExpression(Expression.IDLE);
    this.display.face.feedAudioAmplitude(0);

    // Keep transcript visible a bit after audio ends
    this.transcriptHideTimer = setTimeout(() => {
      this.display.setTranscriptOverlay(false);
      this.responseText = '';
      this.transcriptHideTimer = null;
    }, 4000);
  }

  private scheduleFaceRevert(durationMs: number): void {
    if (this.revertTimer) clearTimeout(this.revertTimer);
    this.revertTimer = setTimeout(() => {
      this.display.face.setExpression(Expression.IDLE);
      this.revertTimer = null;
    }, durationMs);
  }
}
