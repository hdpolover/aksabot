import { Expression, type FaceState } from '../types';

// ── Idle micro-animation types ──

enum IdleAct {
  NONE = 0,
  LOOK_AROUND = 1,
  DOUBLE_BLINK = 2,
  CURIOUS = 3,
  YAWN = 4,
  DISAPPEAR = 5,
  EYE_ROLL = 6,
  WINK = 7,
  BOUNCE = 8,
}

const IDLE_ACT_COUNT = 8;
const BLINK_DURATION_MS = 120;

function flerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function randInt(max: number): number {
  return (Math.random() * max) | 0;
}

function canBlink(e: Expression): boolean {
  return (
    e === Expression.IDLE ||
    e === Expression.SPEAKING ||
    e === Expression.ENCOURAGING ||
    e === Expression.CALM ||
    e === Expression.FOCUSED ||
    e === Expression.HAPPY ||
    e === Expression.OFFLINE
  );
}

// ── FaceAnimator class ──

export class FaceAnimator {
  private state: FaceState;
  private targetExpr = Expression.IDLE;

  // Blink timing
  private nextBlinkMs = 0;
  private blinkStartMs = 0;

  // Transition
  private transitionStartMs = 0;
  private transitionDurationMs = 200;

  // Thinking
  private lastDotTickMs = 0;

  // Pupil drift
  private driftTX = 0;
  private driftTY = 0;
  private nextDriftSwitch = 0;

  // Idle fidget
  private _nextFidgetMs = 0;

  // Idle micro-animations
  private currentAct = IdleAct.NONE;
  private actStartMs = 0;
  private nextActMs = 0;
  private actParam = 0;

  // Sad teardrop
  private lastTearSpawnMs = 0;

  // Speaking amplitude
  private currentAmplitude = 0;

  constructor() {
    this.state = this.defaultState();
  }

  private defaultState(): FaceState {
    return {
      expression: Expression.IDLE,
      eyesOpen: true,
      blinking: false,
      blinkScale: 1.0,
      mouthAmp: 0,
      breathPhase: 0,
      thinkDots: 0,
      driftX: 0,
      driftY: 0,
      fidgetX: 0,
      fidgetY: 0,
      listenPhase: 0,
      bounceY: 0,
      tearActive: false,
      tearY: 0,
      tearSide: -1,
      glowPhase: 0,
      leftEyeScale: 1.0,
      rightEyeScale: 1.0,
      yawnAmp: 0,
      popScale: 1.0,
      transitionActive: false,
      transitionProgress: 1.0,
    };
  }

  init(nowMs: number): void {
    this.state = this.defaultState();
    this.targetExpr = Expression.IDLE;
    this.nextBlinkMs = nowMs + 2000;
    this.nextDriftSwitch = nowMs + 1000;
    this._nextFidgetMs = nowMs + 5000;
    this.nextActMs = nowMs + 5000 + randInt(5000);
    this.lastTearSpawnMs = nowMs;
    this.currentAct = IdleAct.NONE;
  }

  tick(nowMs: number): void {
    const dt = 0.016; // ~60fps

    // ── Transition ──
    if (this.state.transitionActive) {
      const elapsed = nowMs - this.transitionStartMs;
      if (elapsed >= this.transitionDurationMs) {
        this.state.transitionActive = false;
        this.state.transitionProgress = 1.0;
        this.state.expression = this.targetExpr;
      } else {
        this.state.transitionProgress = elapsed / this.transitionDurationMs;
      }
    }

    const active = this.state.transitionActive
      ? this.targetExpr
      : this.state.expression;

    // ── Blink ──
    if (this.state.blinking) {
      const bt = (nowMs - this.blinkStartMs) / BLINK_DURATION_MS;
      if (bt >= 1.0) {
        this.state.blinking = false;
        this.state.blinkScale = 1.0;
        this.state.eyesOpen = true;
        this.nextBlinkMs = nowMs + 3000 + randInt(5000);
      } else {
        if (bt < 0.4) this.state.blinkScale = 1.0 - bt / 0.4;
        else if (bt < 0.6) this.state.blinkScale = 0.0;
        else this.state.blinkScale = (bt - 0.6) / 0.4;
        this.state.eyesOpen = this.state.blinkScale > 0.05;
      }
    } else if (canBlink(active) && nowMs >= this.nextBlinkMs) {
      this.state.blinking = true;
      this.blinkStartMs = nowMs;
    } else if (active === Expression.SLEEPING) {
      this.state.eyesOpen = false;
      this.state.blinkScale = 0.0;
    } else {
      this.state.eyesOpen = true;
      this.state.blinkScale = 1.0;
    }

    // ── Pupil drift ──
    if (
      active === Expression.IDLE ||
      active === Expression.CALM ||
      active === Expression.SPEAKING
    ) {
      this.state.driftX = flerp(this.state.driftX, this.driftTX, 0.03);
      this.state.driftY = flerp(this.state.driftY, this.driftTY, 0.03);
      if (nowMs >= this.nextDriftSwitch) {
        this.driftTX = (Math.random() - 0.5) * 16.0;
        this.driftTY = (Math.random() - 0.5) * 14.0;
        this.nextDriftSwitch = nowMs + 2500 + randInt(3000);
      }
    } else {
      this.state.driftX = flerp(this.state.driftX, 0, 0.1);
      this.state.driftY = flerp(this.state.driftY, 0, 0.1);
    }

    // ── Thinking dots ──
    if (active === Expression.THINKING && nowMs - this.lastDotTickMs >= 400) {
      this.state.thinkDots = (this.state.thinkDots + 1) % 4;
      this.lastDotTickMs = nowMs;
    }

    // ── Breathing ──
    this.state.breathPhase += dt / 4.0;
    if (this.state.breathPhase > 1.0) this.state.breathPhase -= 1.0;

    // ── Mouth amplitude ──
    this.state.mouthAmp = flerp(
      this.state.mouthAmp,
      active === Expression.SPEAKING ? this.currentAmplitude : 0,
      0.25,
    );

    // ── Listening pulse ──
    if (active === Expression.LISTENING) {
      this.state.listenPhase += dt * 4.0;
    }

    // ── Idle micro-animations ──
    this.state.leftEyeScale = 1.0;
    this.state.rightEyeScale = 1.0;
    this.state.yawnAmp = 0.0;
    this.state.popScale = 1.0;

    if (active === Expression.IDLE) {
      this.state.fidgetX = flerp(this.state.fidgetX, 0, 0.05);
      this.state.fidgetY = flerp(this.state.fidgetY, 0, 0.05);

      if (this.currentAct === IdleAct.NONE && nowMs >= this.nextActMs) {
        const pick = randInt(IDLE_ACT_COUNT);
        this.currentAct = (pick + 1) as IdleAct;
        this.actStartMs = nowMs;
        this.actParam = Math.random() < 0.5 ? -1 : 1;
      }

      if (this.currentAct !== IdleAct.NONE) {
        const t = nowMs - this.actStartMs;
        this.runIdleAct(t);

        if ((this.currentAct as IdleAct) === IdleAct.NONE) {
          this.nextActMs = nowMs + 8000 + randInt(12000);
        }
      }
    } else {
      this.state.fidgetX = flerp(this.state.fidgetX, 0, 0.1);
      this.state.fidgetY = flerp(this.state.fidgetY, 0, 0.1);
      if (this.currentAct !== IdleAct.NONE) {
        this.currentAct = IdleAct.NONE;
        this.nextActMs = 0;
      }
    }

    // ── Bounce / nod ──
    if (active === Expression.HAPPY) {
      this.state.bounceY = Math.sin(nowMs / 300.0) * 4.0;
    } else if (active === Expression.LISTENING) {
      this.state.bounceY = Math.sin(nowMs / 600.0) * 3.0;
    } else if (this.currentAct !== IdleAct.BOUNCE) {
      this.state.bounceY = flerp(this.state.bounceY, 0, 0.1);
    }

    // ── Sad teardrop ──
    if (active === Expression.SAD) {
      if (this.state.tearActive) {
        this.state.tearY += 1.5;
        if (this.state.tearY > 60) this.state.tearActive = false;
      } else if (nowMs - this.lastTearSpawnMs > 3000 + randInt(2000)) {
        this.state.tearActive = true;
        this.state.tearY = 10;
        this.state.tearSide = Math.random() < 0.5 ? -1 : 1;
        this.lastTearSpawnMs = nowMs;
      }
    } else {
      this.state.tearActive = false;
    }

    // ── Glow pulse ──
    this.state.glowPhase += dt * 1.5;
    if (this.state.glowPhase > 6.2832) this.state.glowPhase -= 6.2832;
  }

  private runIdleAct(t: number): void {
    switch (this.currentAct) {
      case IdleAct.LOOK_AROUND: {
        const phase = t / 2500.0;
        if (phase < 0.25) {
          this.driftTX = -20.0;
          this.driftTY = 0;
        } else if (phase < 0.5) {
          this.driftTX = -20.0;
        } else if (phase < 0.75) {
          this.driftTX = 20.0;
        } else if (phase < 1.0) {
          this.driftTX = 0;
          this.driftTY = 0;
        } else {
          this.currentAct = IdleAct.NONE;
        }
        break;
      }

      case IdleAct.DOUBLE_BLINK: {
        if (t < 120) this.state.blinkScale = 1.0 - t / 120.0;
        else if (t < 200) this.state.blinkScale = 0.0;
        else if (t < 300) this.state.blinkScale = (t - 200) / 100.0;
        else if (t < 350) this.state.blinkScale = 1.0;
        else if (t < 470) this.state.blinkScale = 1.0 - (t - 350) / 120.0;
        else if (t < 550) this.state.blinkScale = 0.0;
        else if (t < 650) this.state.blinkScale = (t - 550) / 100.0;
        else {
          this.state.blinkScale = 1.0;
          this.currentAct = IdleAct.NONE;
        }
        this.state.eyesOpen = this.state.blinkScale > 0.05;
        break;
      }

      case IdleAct.CURIOUS: {
        const phase = t / 2000.0;
        if (phase < 0.3) {
          const ease = phase / 0.3;
          this.state.leftEyeScale = 1.0 + ease * 0.2;
          this.state.rightEyeScale = 1.0 + ease * 0.2;
          this.driftTX = this.actParam * 18.0 * ease;
          this.driftTY = -4.0 * ease;
        } else if (phase < 0.7) {
          this.state.leftEyeScale = 1.2;
          this.state.rightEyeScale = 1.2;
          this.driftTX = this.actParam * 18.0;
          this.driftTY = -4.0;
        } else if (phase < 1.0) {
          const ease = (phase - 0.7) / 0.3;
          this.state.leftEyeScale = 1.2 - ease * 0.2;
          this.state.rightEyeScale = 1.2 - ease * 0.2;
          this.driftTX = this.actParam * 18.0 * (1.0 - ease);
          this.driftTY = -4.0 * (1.0 - ease);
        } else {
          this.currentAct = IdleAct.NONE;
        }
        break;
      }

      case IdleAct.YAWN: {
        const phase = t / 2500.0;
        if (phase < 0.2) {
          const ease = phase / 0.2;
          this.state.leftEyeScale = 1.0 - ease * 0.6;
          this.state.rightEyeScale = 1.0 - ease * 0.6;
          this.state.yawnAmp = ease * 0.8;
        } else if (phase < 0.6) {
          this.state.leftEyeScale = 0.4;
          this.state.rightEyeScale = 0.4;
          this.state.yawnAmp = 0.8;
        } else if (phase < 1.0) {
          const ease = (phase - 0.6) / 0.4;
          this.state.leftEyeScale = 0.4 + ease * 0.6;
          this.state.rightEyeScale = 0.4 + ease * 0.6;
          this.state.yawnAmp = 0.8 * (1.0 - ease);
        } else {
          this.currentAct = IdleAct.NONE;
        }
        break;
      }

      case IdleAct.DISAPPEAR: {
        const phase = t / 2000.0;
        if (phase < 0.25) {
          this.state.popScale = 1.0 - phase / 0.25;
        } else if (phase < 0.55) {
          this.state.popScale = 0.0;
        } else if (phase < 0.75) {
          const ease = (phase - 0.55) / 0.2;
          this.state.popScale = ease * 1.15;
        } else if (phase < 1.0) {
          const ease = (phase - 0.75) / 0.25;
          this.state.popScale = 1.15 - ease * 0.15;
        } else {
          this.state.popScale = 1.0;
          this.currentAct = IdleAct.NONE;
        }
        break;
      }

      case IdleAct.EYE_ROLL: {
        const phase = t / 1500.0;
        if (phase < 1.0) {
          const angle = phase * 2.0 * Math.PI;
          this.driftTX = Math.cos(angle) * 14.0;
          this.driftTY = Math.sin(angle) * 10.0;
        } else {
          this.driftTX = 0;
          this.driftTY = 0;
          this.currentAct = IdleAct.NONE;
        }
        break;
      }

      case IdleAct.WINK: {
        const phase = t / 800.0;
        let scale: number;
        if (phase < 0.25) scale = 1.0 - phase / 0.25;
        else if (phase < 0.6) scale = 0.0;
        else if (phase < 1.0) scale = (phase - 0.6) / 0.4;
        else {
          scale = 1.0;
          this.currentAct = IdleAct.NONE;
        }

        if (this.actParam > 0) this.state.rightEyeScale = scale;
        else this.state.leftEyeScale = scale;
        break;
      }

      case IdleAct.BOUNCE: {
        const phase = t / 800.0;
        if (phase < 0.3) {
          this.state.bounceY = -Math.sin((phase / 0.3) * Math.PI) * 8.0;
        } else if (phase < 0.6) {
          this.state.bounceY =
            -Math.sin(((phase - 0.3) / 0.3) * Math.PI) * 3.0;
        } else if (phase < 1.0) {
          this.state.bounceY = flerp(this.state.bounceY, 0, 0.15);
        } else {
          this.state.bounceY = 0;
          this.currentAct = IdleAct.NONE;
        }
        break;
      }

      default:
        this.currentAct = IdleAct.NONE;
        break;
    }
  }

  setExpression(expr: Expression, transitionMs = 200): void {
    if (expr === this.targetExpr && !this.state.transitionActive) return;
    this.targetExpr = expr;

    const now = performance.now();
    if (transitionMs === 0) {
      this.state.expression = expr;
      this.state.transitionActive = false;
    } else {
      this.state.transitionActive = true;
      this.state.transitionProgress = 0.0;
      this.transitionStartMs = now;
      this.transitionDurationMs = transitionMs;
    }

    // Reset expression-specific state
    this.state.thinkDots = 0;
    this.lastDotTickMs = now;
    this.state.tearActive = false;
    this.state.bounceY = 0;
  }

  feedAudioAmplitude(amplitude: number): void {
    this.currentAmplitude = Math.max(0, Math.min(1, amplitude));
  }

  getState(): Readonly<FaceState> {
    return this.state;
  }

  getExpression(): Expression {
    return this.state.expression;
  }
}
