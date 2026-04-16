import {
  Expression,
  EXPRESSION_NAMES,
  type FaceState,
  type StatusBar,
  type RGB,
  type Palette,
  type EyeShape,
  LCD_WIDTH,
  LCD_HEIGHT,
  CX,
  CY,
  EYE_SPACE,
  MOUTH_Y,
} from '../types';
import { PAL, EYES } from '../face/constants';
import { tftFont } from './text';

// ── Color helpers ──

function rgbStr(c: RGB): string {
  return `rgb(${c.r},${c.g},${c.b})`;
}

function blend(fg: RGB, bg: RGB, alpha: number): RGB {
  const a = alpha / 255;
  return {
    r: Math.round(fg.r * a + bg.r * (1 - a)),
    g: Math.round(fg.g * a + bg.g * (1 - a)),
    b: Math.round(fg.b * a + bg.b * (1 - a)),
  };
}

function constrain(val: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, val));
}

const WHITE: RGB = { r: 255, g: 255, b: 255 };
const BLACK: RGB = { r: 0, g: 0, b: 0 };

// ── Bezier helpers ──

function bezierPt(
  t: number,
  x0: number,
  y0: number,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
): [number, number] {
  const mt = 1.0 - t;
  return [
    mt * mt * x0 + 2 * mt * t * x1 + t * t * x2,
    mt * mt * y0 + 2 * mt * t * y1 + t * t * y2,
  ];
}

function thickBezier(
  ctx: CanvasRenderingContext2D,
  x0: number,
  y0: number,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  radius: number,
  color: RGB,
  steps = 24,
): void {
  ctx.fillStyle = rgbStr(color);
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const [px, py] = bezierPt(t, x0, y0, x1, y1, x2, y2);
    ctx.beginPath();
    ctx.arc(px, py, radius, 0, Math.PI * 2);
    ctx.fill();
  }
}

function drawGlow(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  maxR: number,
  color: RGB,
  bg: RGB,
  peakAlpha = 80,
): void {
  for (let i = 0; i < 6; i++) {
    const r = maxR - i * (maxR / 6);
    if (r < 1) continue;
    const a = ((peakAlpha / 6) * (i + 1)) / 255;
    ctx.fillStyle = rgbStr(blend(color, bg, ((peakAlpha / 6) * (i + 1))));
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
}

// ── Eye rendering ──

function drawEyeOpen(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  eye: EyeShape,
  scaleY: number,
  pupilDX: number,
  pupilDY: number,
  _pal: Palette,
): void {
  const r = eye.r;
  const rh = Math.round(r * scaleY);

  if (rh < 4) {
    // Nearly closed — draw as bezier arc
    thickBezier(ctx, cx - r, cy, cx, cy + 4, cx + r, cy, 2, WHITE, 16);
    return;
  }

  // Sclera
  ctx.fillStyle = rgbStr(WHITE);
  ctx.beginPath();
  if (rh < r) {
    ctx.ellipse(cx, cy, r, rh, 0, 0, Math.PI * 2);
  } else {
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
  }
  ctx.fill();

  // Pupil position (constrained within eye)
  let px = cx + eye.pupilOX + Math.round(pupilDX);
  let py = cy + eye.pupilOY + Math.round(pupilDY);
  let maxOff = r - eye.pupilR - 1;
  if (maxOff < 3) maxOff = 3;
  px = constrain(px, cx - maxOff, cx + maxOff);
  py = constrain(py, cy - maxOff, cy + maxOff);

  // Pupil
  ctx.fillStyle = rgbStr(BLACK);
  ctx.beginPath();
  ctx.arc(px, py, eye.pupilR, 0, Math.PI * 2);
  ctx.fill();

  // Highlight
  ctx.fillStyle = rgbStr(WHITE);
  ctx.beginPath();
  ctx.arc(px - 3, py - 3, 2, 0, Math.PI * 2);
  ctx.fill();
}

function drawEyeClosed(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  r: number,
  curveUp: boolean,
): void {
  const bend = curveUp ? -5.0 : 4.0;
  thickBezier(ctx, cx - r, cy, cx, cy + bend, cx + r, cy, 2, WHITE, 20);
}

function drawEyeX(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  size: number,
  color: RGB,
): void {
  const hs = size / 2;
  ctx.strokeStyle = rgbStr(color);
  ctx.lineWidth = 4;
  ctx.lineCap = 'round';

  ctx.beginPath();
  ctx.moveTo(cx - hs, cy - hs);
  ctx.lineTo(cx + hs, cy + hs);
  ctx.stroke();

  ctx.beginPath();
  ctx.moveTo(cx + hs, cy - hs);
  ctx.lineTo(cx - hs, cy + hs);
  ctx.stroke();
}

function drawBrow(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  r: number,
  accent: RGB,
  raised: boolean,
): void {
  const by = cy - r - 6;
  const bend = raised ? -7.0 : -3.0;
  thickBezier(ctx, cx - 14, by, cx, by + bend, cx + 14, by, 2, accent, 16);
}

// ── Mouth rendering ──

function drawMouth(
  ctx: CanvasRenderingContext2D,
  expr: Expression,
  pal: Palette,
  amp: number,
  bounceY: number,
  breathPhase: number,
): void {
  const my = MOUTH_Y + Math.round(bounceY);

  switch (expr) {
    case Expression.IDLE: {
      const breathOff = Math.sin(breathPhase * 2 * Math.PI) * 1.5;
      thickBezier(ctx, CX - 20, my, CX, my + 8 + breathOff, CX + 20, my, 2, pal.mouth);
      break;
    }

    case Expression.LISTENING: {
      // Outer ooh
      ctx.fillStyle = rgbStr(pal.mouth);
      ctx.beginPath();
      ctx.ellipse(CX, my, 7, 9, 0, 0, Math.PI * 2);
      ctx.fill();
      // Inner
      const inside = blend(pal.accent, pal.bg, 40);
      ctx.fillStyle = rgbStr(inside);
      ctx.beginPath();
      ctx.ellipse(CX, my, 4, 6, 0, 0, Math.PI * 2);
      ctx.fill();
      break;
    }

    case Expression.THINKING: {
      ctx.fillStyle = rgbStr(pal.mouth);
      ctx.beginPath();
      ctx.arc(CX + 8, my, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = rgbStr(blend(pal.accent, pal.bg, 50));
      ctx.beginPath();
      ctx.arc(CX + 8, my, 2, 0, Math.PI * 2);
      ctx.fill();
      break;
    }

    case Expression.SPEAKING: {
      let a = amp * 2.5;
      if (a > 1.0) a = 1.0;
      const ow = 24 + Math.round(a * 12);
      const oh = 8 + Math.round(a * 24);

      // Outer mouth
      ctx.fillStyle = rgbStr(pal.mouth);
      ctx.beginPath();
      ctx.ellipse(CX, my, ow / 2, oh / 2, 0, 0, Math.PI * 2);
      ctx.fill();

      // Inner cavity
      if (oh > 12) {
        ctx.fillStyle = rgbStr(blend(pal.accent, pal.bg, 25));
        ctx.beginPath();
        ctx.ellipse(CX, my + 1, ow / 2 - 4, oh / 2 - 4, 0, 0, Math.PI * 2);
        ctx.fill();
      }

      // Upper lip
      ctx.fillStyle = rgbStr(pal.mouth);
      ctx.beginPath();
      ctx.ellipse(CX, my - oh / 2 + 2, ow / 2 - 2, 3, 0, 0, Math.PI * 2);
      ctx.fill();
      break;
    }

    case Expression.CONFUSED: {
      // Wavy line
      ctx.fillStyle = rgbStr(pal.mouth);
      for (let i = 0; i <= 36; i++) {
        const t = i / 36;
        const wx = CX - 18 + Math.round(36 * t);
        const wy = my + Math.round(4.0 * Math.sin(t * Math.PI * 2.5));
        ctx.beginPath();
        ctx.arc(wx, wy, 2, 0, Math.PI * 2);
        ctx.fill();
      }
      // Small "?" next to mouth — textSize 3
      ctx.font = tftFont(3);
      ctx.fillStyle = rgbStr(pal.accent);
      ctx.textBaseline = 'top';
      ctx.fillText('?', CX + 30, my - 20);
      ctx.textBaseline = 'alphabetic';
      break;
    }

    case Expression.SLEEPING: {
      const bOff = Math.sin(breathPhase * 2 * Math.PI) * 5;
      ctx.fillStyle = rgbStr(pal.accent);
      ctx.textBaseline = 'top';
      ctx.font = tftFont(2); // textSize 2 → 16px
      ctx.fillText('z', CX + 22, my - 5 + bOff);
      ctx.font = tftFont(3); // textSize 3 → 24px
      ctx.fillText('Z', CX + 35, my - 25 + bOff * 0.7);
      ctx.textBaseline = 'alphabetic';
      break;
    }

    case Expression.OFFLINE: {
      thickBezier(ctx, CX - 18, my, CX, my, CX + 18, my, 2, pal.mouth);
      break;
    }

    case Expression.ENCOURAGING: {
      thickBezier(ctx, CX - 24, my, CX, my + 14, CX + 24, my, 3, pal.mouth);
      // Teeth gleam
      thickBezier(
        ctx, CX - 14, my + 2, CX, my + 9, CX + 14, my + 2, 2,
        blend(WHITE, pal.mouth, 120), 14,
      );
      break;
    }

    case Expression.CALM: {
      thickBezier(ctx, CX - 22, my + 2, CX, my + 5, CX + 22, my + 2, 3, pal.mouth);
      break;
    }

    case Expression.FOCUSED: {
      thickBezier(ctx, CX - 16, my, CX - 5, my + 1, CX + 5, my + 1, 2, pal.mouth);
      thickBezier(ctx, CX + 5, my + 1, CX + 16, my, CX + 16, my, 2, pal.mouth);
      break;
    }

    case Expression.HAPPY: {
      thickBezier(ctx, CX - 26, my, CX, my + 16, CX + 26, my, 3, pal.mouth);
      thickBezier(
        ctx, CX - 16, my + 2, CX, my + 10, CX + 16, my + 2, 2,
        blend(WHITE, pal.mouth, 160), 16,
      );
      break;
    }

    case Expression.SAD: {
      const trem = Math.sin(breathPhase * 6.28318 * 3) * 1.0;
      thickBezier(ctx, CX - 18, my + 4, CX, my - 6 + trem, CX + 18, my + 4, 2, pal.mouth);
      break;
    }
  }
}

// ── Main face renderer ──

export function renderFace(
  ctx: CanvasRenderingContext2D,
  fs: Readonly<FaceState>,
  status: StatusBar,
): void {
  const exprIdx = constrain(fs.expression, 0, 11);
  const pal = PAL[exprIdx];
  const eye = EYES[exprIdx];

  // Clear with expression-specific background
  ctx.fillStyle = rgbStr(pal.bg);
  ctx.fillRect(0, 0, LCD_WIDTH, LCD_HEIGHT);

  // Ambient glow
  const gp = Math.sin(fs.glowPhase) * 0.3 + 0.7;
  drawGlow(ctx, CX, CY, 60, pal.accent, pal.bg, Math.round(8 * gp));

  // Apply popScale
  const ps = fs.popScale;
  const eyeSpace = Math.round(EYE_SPACE * ps);
  const faceOY = Math.round(fs.bounceY * ps);
  const leftEyeX = CX - eyeSpace + Math.round(fs.fidgetX * ps);
  const rightEyeX = CX + eyeSpace + Math.round(fs.fidgetX * ps);
  const eyeY = CY + faceOY + Math.round(fs.fidgetY * ps);

  // Skip face if fully popped away
  if (ps >= 0.01) {
    // Per-eye scale
    const leftScale = fs.blinkScale * fs.leftEyeScale * ps;
    const rightScale = fs.blinkScale * fs.rightEyeScale * ps;

    // Scaled eye shapes
    const leftEye: EyeShape = {
      ...eye,
      r: Math.round(eye.r * fs.leftEyeScale * ps),
      pupilR: Math.round(eye.pupilR * fs.leftEyeScale * ps),
    };
    const rightEye: EyeShape = {
      ...eye,
      r: Math.round(eye.r * fs.rightEyeScale * ps),
      pupilR: Math.round(eye.pupilR * fs.rightEyeScale * ps),
    };

    if (fs.expression === Expression.SLEEPING) {
      const bOff = Math.sin(fs.breathPhase * 2 * Math.PI) * 3;
      drawEyeClosed(ctx, leftEyeX, eyeY + bOff, 24, false);
      drawEyeClosed(ctx, rightEyeX, eyeY + bOff, 24, false);
    } else if (fs.expression === Expression.OFFLINE) {
      drawEyeOpen(ctx, leftEyeX, eyeY, leftEye, 1.0, fs.driftX, fs.driftY, pal);
      drawEyeOpen(ctx, rightEyeX, eyeY, rightEye, 1.0, fs.driftX, fs.driftY, pal);
      drawEyeX(ctx, leftEyeX, eyeY, 20, pal.accent);
      drawEyeX(ctx, rightEyeX, eyeY, 20, pal.accent);
    } else {
      // Left eye
      if (leftScale < 0.05) {
        const curveUp =
          fs.expression === Expression.HAPPY ||
          fs.expression === Expression.ENCOURAGING;
        drawEyeClosed(ctx, leftEyeX, eyeY, leftEye.r, curveUp);
      } else {
        drawEyeOpen(ctx, leftEyeX, eyeY, leftEye, leftScale, fs.driftX, fs.driftY, pal);
      }
      // Right eye
      if (rightScale < 0.05) {
        const curveUp =
          fs.expression === Expression.HAPPY ||
          fs.expression === Expression.ENCOURAGING;
        drawEyeClosed(ctx, rightEyeX, eyeY, rightEye.r, curveUp);
      } else {
        drawEyeOpen(ctx, rightEyeX, eyeY, rightEye, rightScale, fs.driftX, fs.driftY, pal);
      }
      // Brows
      if (eye.hasBrows) {
        const raised = fs.expression === Expression.HAPPY;
        drawBrow(ctx, leftEyeX, eyeY, leftEye.r, pal.accent, raised);
        drawBrow(ctx, rightEyeX, eyeY, rightEye.r, pal.accent, raised);
      }
    }

    // Mouth
    if (fs.yawnAmp > 0.01) {
      const my = MOUTH_Y + Math.round(fs.bounceY * ps);
      const ow = Math.round(12 + fs.yawnAmp * 14);
      const oh = Math.round(4 + fs.yawnAmp * 20);
      ctx.fillStyle = rgbStr(pal.mouth);
      ctx.beginPath();
      ctx.ellipse(CX, my, ow, oh, 0, 0, Math.PI * 2);
      ctx.fill();
      if (oh > 6) {
        ctx.fillStyle = rgbStr(blend(pal.accent, pal.bg, 30));
        ctx.beginPath();
        ctx.ellipse(CX, my, ow - 3, oh - 3, 0, 0, Math.PI * 2);
        ctx.fill();
      }
    } else {
      drawMouth(ctx, fs.expression, pal, fs.mouthAmp, fs.bounceY * ps, fs.breathPhase);
    }
  }

  // Thinking dots
  if (fs.expression === Expression.THINKING) {
    const dy = MOUTH_Y + 5;
    for (let i = 0; i < 3; i++) {
      const dx = CX - 15 + i * 15;
      const lit = i < fs.thinkDots;
      const col = lit ? pal.accent : blend(pal.accent, pal.bg, 30);
      ctx.fillStyle = rgbStr(col);
      ctx.beginPath();
      ctx.arc(dx, dy, lit ? 4 : 3, 0, Math.PI * 2);
      ctx.fill();
      if (lit) drawGlow(ctx, dx, dy, 8, pal.accent, pal.bg, 30);
    }
  }

  // Listening pulse
  if (fs.expression === Expression.LISTENING) {
    const ly = LCD_HEIGHT - 45;
    const pulse = Math.sin(fs.listenPhase) * 0.5 + 0.5;
    const r = 6 + Math.round(pulse * 5);
    drawGlow(ctx, CX, ly, r + 10, pal.accent, pal.bg, Math.round(30 + pulse * 40));
    ctx.fillStyle = rgbStr(pal.accent);
    ctx.beginPath();
    ctx.arc(CX, ly, r, 0, Math.PI * 2);
    ctx.fill();
  }

  // Sad teardrop
  if (fs.tearActive) {
    const tx = CX + fs.tearSide * EYE_SPACE;
    const ty = CY + Math.round(fs.tearY);
    const tearCol = blend({ r: 100, g: 150, b: 255 }, pal.bg, 180);
    ctx.fillStyle = rgbStr(tearCol);
    ctx.beginPath();
    ctx.arc(tx, ty + 3, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(tx - 2, ty + 2);
    ctx.lineTo(tx + 2, ty + 2);
    ctx.lineTo(tx, ty - 3);
    ctx.closePath();
    ctx.fill();
  }

  // Confused question mark (floating)
  if (fs.expression === Expression.CONFUSED) {
    const t = fs.glowPhase * 1.5;
    const bobY = Math.sin(t) * 6.0;
    const tiltX = Math.sin(t * 0.7) * 4.0;
    const scale = 1.0 + Math.sin(t * 2.0) * 0.1;

    const qx = CX + 35 + tiltX;
    const qy = eyeY - 50 + bobY;

    const glowAlpha = Math.round(20 + Math.sin(t * 2.0) * 15);
    drawGlow(ctx, qx, qy + 5, Math.round(20 * scale), pal.accent, pal.bg, glowAlpha);

    const textSize = Math.max(2, Math.round(3 * scale));
    ctx.font = tftFont(textSize);
    ctx.fillStyle = rgbStr(pal.accent);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('?', qx, qy);
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
  }

  // Connection dot (top-left)
  let dotCol: RGB;
  if (status.wifiConnected && status.wsConnected) dotCol = { r: 0, g: 200, b: 80 };
  else if (status.wifiConnected) dotCol = { r: 220, g: 180, b: 0 };
  else dotCol = { r: 200, g: 50, b: 40 };
  ctx.fillStyle = rgbStr(dotCol);
  ctx.beginPath();
  ctx.arc(8, 8, 4, 0, Math.PI * 2);
  ctx.fill();

  // Expression label (bottom) — textSize 2
  const name = EXPRESSION_NAMES[exprIdx];
  if (name) {
    ctx.fillStyle = rgbStr(pal.label);
    ctx.font = tftFont(2);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(name, CX, LCD_HEIGHT - 28);
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
  }
}
