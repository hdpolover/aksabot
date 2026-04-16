import { Expression } from '../types';
import { useFaceStore } from './faceStore';
import { useConversationStore } from './conversationStore';
import { audioStore } from './audioStore';

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

let revertTimer: ReturnType<typeof setTimeout> | null = null;

function scheduleRevert(durationMs: number) {
  if (revertTimer) clearTimeout(revertTimer);
  revertTimer = setTimeout(() => {
    useFaceStore.getState().setExpression(Expression.IDLE);
    revertTimer = null;
  }, durationMs);
}

export function handleWsEvent(
  event: string,
  data: Record<string, unknown>,
  send: (event: string, data?: Record<string, unknown>) => void,
): void {
  const face = useFaceStore.getState();
  const convo = useConversationStore.getState();
  const { audioPlayer, setPlaying } = audioStore.getState();

  switch (event) {
    case 'state:update': {
      if (audioStore.getState().isPlaying) break;
      const expr = STATE_TO_EXPR[data.state as string];
      if (expr !== undefined) face.setExpression(expr);
      break;
    }

    case 'face:expression': {
      const expr = EXPR_MAP[(data.expression as string)?.toLowerCase()];
      if (expr !== undefined) {
        face.setExpression(expr);
        const ms = data.durationMs as number | undefined;
        if (ms && ms > 0) scheduleRevert(ms);
      }
      break;
    }

    case 'response:start': {
      convo.startResponse();
      face.setExpression(Expression.SPEAKING);
      setPlaying(true);
      audioPlayer.startPlayback(() => {
        // All audio finished playing
        face.setExpression(Expression.IDLE);
        audioPlayer.stop();
        setPlaying(false);
        convo.commitResponse();
      });
      break;
    }

    case 'response:text': {
      convo.appendResponse((data.text as string) ?? '');
      break;
    }

    case 'response:end': {
      audioPlayer.markSendingDone();
      break;
    }

    case 'transcript:partial': {
      convo.setPartialTranscript(((data.text as string) ?? '') + '…');
      break;
    }

    case 'transcript:final': {
      const text = (data.text as string) ?? '';
      convo.addMessage('user', text);
      convo.setPartialTranscript(null);
      break;
    }

    case 'proactive:reminder':
    case 'proactive:nudge':
    case 'proactive:briefing': {
      const display = data.display as Record<string, unknown> | undefined;
      const exprName = (display?.expression as string | undefined)?.toLowerCase();
      if (exprName && EXPR_MAP[exprName] !== undefined) {
        face.setExpression(EXPR_MAP[exprName]);
      }
      face.showProactive({
        type: event === 'proactive:reminder' ? 'reminder' : event === 'proactive:nudge' ? 'nudge' : 'briefing',
        text: (data.text as string) ?? '',
        durationMs: (display?.durationMs as number) ?? 8000,
      });
      break;
    }

    case 'proactive:pomodoro': {
      const action = data.action as string;
      if (action === 'stop') {
        face.setExpression(Expression.IDLE);
        face.dismissProactive();
      } else {
        const phase = (data.phase as string) ?? 'focus';
        const isFocus = phase === 'focus' || phase === 'work';
        face.setExpression(isFocus ? Expression.FOCUSED : Expression.CALM);
        face.showProactive({
          type: 'pomodoro',
          text: isFocus ? 'Focus time' : 'Break time',
          durationMs: 0,
          pomodoroPhase: phase,
          pomodoroRemaining: Math.round(((data.durationMs as number) ?? 1500000) / 1000),
          pomodoroCycle: (data.cycle as number) ?? 1,
          pomodoroTotalCycles: 4,
        });
      }
      break;
    }

    case 'focus:start':
      face.setExpression(Expression.FOCUSED);
      break;

    case 'focus:end':
      face.setExpression(Expression.IDLE);
      break;

    case 'error':
      face.setExpression(Expression.CONFUSED);
      scheduleRevert(2500);
      break;

    case 'config:update':
      // Future: apply config updates (volume, brightness, etc.)
      break;

    default:
      break;
  }

  void send; // suppress unused warning — reserved for future client→server replies
}
