import {
  type StatusBar,
  type PomodoroData,
  type ReminderData,
  type CountdownData,
  LCD_WIDTH,
  LCD_HEIGHT,
  CX,
  CY,
} from '../types';
import { tftFont, drawWrappedText, wordWrap } from './text';

const BG = '#000';
const WHITE = '#fff';
const DIM = 'rgb(80,80,80)';
const ACCENT = 'rgb(0,255,255)';
const CALM = 'rgb(0,255,0)';
const WARM = 'rgb(255,255,0)';
const STATUS_BG = 'rgb(20,20,30)';

export function renderClock(ctx: CanvasRenderingContext2D, _status: StatusBar): void {
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, LCD_WIDTH, LCD_HEIGHT);

  const now = new Date();
  const h = String(now.getHours()).padStart(2, '0');
  const m = String(now.getMinutes()).padStart(2, '0');

  // textSize 5 → 40px height
  ctx.font = tftFont(5);
  ctx.fillStyle = WHITE;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(`${h}:${m}`, CX, CY - 20);

  // textSize 2 → 16px height
  ctx.font = tftFont(2);
  ctx.fillStyle = DIM;
  ctx.fillText('Aksabot', CX, CY + 30);

  ctx.textAlign = 'start';
  ctx.textBaseline = 'alphabetic';
}

export function renderPomodoro(ctx: CanvasRenderingContext2D, data: PomodoroData): void {
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, LCD_WIDTH, LCD_HEIGHT);

  const isFocus = data.phaseLabel.toLowerCase() === 'focus' || data.phaseLabel.toLowerCase() === 'work';

  // Phase label — textSize 3
  ctx.font = tftFont(3);
  ctx.fillStyle = isFocus ? ACCENT : CALM;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(isFocus ? 'FOCUS' : 'BREAK', CX, 60);

  // Countdown — textSize 6
  const min = String(Math.floor(data.remainingSeconds / 60)).padStart(2, '0');
  const sec = String(data.remainingSeconds % 60).padStart(2, '0');
  ctx.font = tftFont(6);
  ctx.fillStyle = WHITE;
  ctx.fillText(`${min}:${sec}`, CX, CY);

  // Cycle dots
  const dotY = CY + 60;
  for (let i = 0; i < data.totalCycles; i++) {
    ctx.fillStyle = i < data.currentCycle ? ACCENT : DIM;
    ctx.beginPath();
    ctx.arc(CX - 30 + i * 20, dotY, 6, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.textAlign = 'start';
  ctx.textBaseline = 'alphabetic';
}

export function renderReminder(ctx: CanvasRenderingContext2D, data: ReminderData): void {
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, LCD_WIDTH, LCD_HEIGHT);

  // Icon — textSize 3
  ctx.font = tftFont(3);
  ctx.fillStyle = WARM;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('!', CX, 40);

  // Reminder text — textSize 2 with word wrap
  const marginX = 10;
  const maxW = LCD_WIDTH - marginX * 2;
  drawWrappedText(ctx, data.text, marginX, 75, maxW, 2, WHITE);

  // Dismiss hint — textSize 1
  ctx.font = tftFont(1);
  ctx.fillStyle = DIM;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('tap to dismiss', CX, LCD_HEIGHT - 20);

  ctx.textAlign = 'start';
  ctx.textBaseline = 'alphabetic';
}

export function renderCountdown(ctx: CanvasRenderingContext2D, data: CountdownData): void {
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, LCD_WIDTH, LCD_HEIGHT);

  // Large number — textSize 8
  ctx.font = tftFont(8);
  ctx.fillStyle = CALM;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(String(data.remainingSeconds), CX, CY - 20);

  // Instruction — textSize 2 with word wrap, centered
  const marginX = 10;
  const maxW = LCD_WIDTH - marginX * 2;
  const lines = wordWrap(data.instruction, 2, maxW);
  const lineH = 18;
  let y = CY + 30;
  ctx.font = tftFont(2);
  ctx.fillStyle = WHITE;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  for (const line of lines) {
    ctx.fillText(line, CX, y);
    y += lineH;
  }

  ctx.textAlign = 'start';
  ctx.textBaseline = 'alphabetic';
}

export function renderStatus(ctx: CanvasRenderingContext2D, status: StatusBar): void {
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, LCD_WIDTH, LCD_HEIGHT);

  ctx.textAlign = 'start';
  ctx.textBaseline = 'top';
  let y = 20;
  const lineH = 24;

  // textSize 2
  ctx.font = tftFont(2);
  ctx.fillStyle = ACCENT;
  ctx.fillText('System Status', 10, y);
  y += lineH + 10;

  ctx.fillStyle = WHITE;
  ctx.fillText(status.wifiConnected ? 'WiFi: Connected' : 'WiFi: Offline', 10, y);
  y += lineH;
  ctx.fillText(status.wsConnected ? 'Backend: Online' : 'Backend: Offline', 10, y);
  y += lineH;
  ctx.fillText(`Signal: ${status.wifiRssi} dBm`, 10, y);
  y += lineH;

  if (status.batteryPercent === 255) {
    ctx.fillText('Power: USB', 10, y);
  } else {
    ctx.fillText(`Battery: ${status.batteryPercent}%`, 10, y);
  }
}

export function renderTranscriptOverlay(
  ctx: CanvasRenderingContext2D,
  speaker: string,
  text: string,
): void {
  const barH = 60;
  const barY = LCD_HEIGHT - barH;

  ctx.fillStyle = STATUS_BG;
  ctx.fillRect(0, barY, LCD_WIDTH, barH);

  // Speaker label — textSize 1
  ctx.font = tftFont(1);
  ctx.fillStyle = ACCENT;
  ctx.textAlign = 'start';
  ctx.textBaseline = 'top';
  ctx.fillText(speaker, 8, barY + 4);

  // Transcript text — textSize 1, word-wrapped within the bar
  const marginX = 8;
  const maxW = LCD_WIDTH - marginX * 2;
  const lines = wordWrap(text, 1, maxW);
  ctx.fillStyle = WHITE;
  let y = barY + 16;
  const lineH = 10;
  // Show at most 4 lines (fit within 60px bar)
  const maxLines = Math.min(lines.length, 4);
  // If more than 4 lines, show the last 4
  const startLine = Math.max(0, lines.length - maxLines);
  for (let i = startLine; i < lines.length; i++) {
    ctx.fillText(lines[i], marginX, y);
    y += lineH;
  }
}
