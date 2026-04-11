import { Expression, LCD_WIDTH, LCD_HEIGHT } from './types';
import { DisplayManager } from './display/DisplayManager';
import { WsClient } from './ws/WsClient';
import { EventHandler } from './ws/EventHandler';
import { AudioPlayer } from './ws/AudioPlayer';
import { AudioRecorder } from './ws/AudioRecorder';

// ── Canvas setup ──

const canvas = document.getElementById('display') as HTMLCanvasElement;
canvas.width = LCD_WIDTH;
canvas.height = LCD_HEIGHT;
const ctx = canvas.getContext('2d')!;

// ── Display manager ──

const display = new DisplayManager(ctx);
display.init(performance.now());

// ── Log ──

const logEl = document.getElementById('log') as HTMLDivElement;
function log(msg: string): void {
  const line = document.createElement('div');
  line.textContent = `[${new Date().toLocaleTimeString()}] ${msg}`;
  logEl.appendChild(line);
  if (logEl.children.length > 50) logEl.removeChild(logEl.firstChild!);
  logEl.scrollTop = logEl.scrollHeight;
}

// ── Audio player (decodes Opus from backend → browser speakers) ──

const audioPlayer = new AudioPlayer((amp) => {
  display.face.feedAudioAmplitude(amp);
});

// ── Audio recorder (mic → PCM → backend) ──

let ws: WsClient; // forward ref

const audioRecorder = new AudioRecorder((pcmBuffer) => {
  ws.sendBinary(pcmBuffer);
});

// ── WebSocket ──

const eventHandler = new EventHandler(display, audioPlayer, log);

ws = new WsClient(
  // JSON events
  (event, data) => {
    eventHandler.handle(event, data);
  },
  // Binary messages (Opus frames from backend)
  async (data) => {
    if (audioPlayer.isPlaying()) {
      await audioPlayer.feedOpusFrame(data);
    }
  },
  // Connection status
  (connected) => {
    display.statusBar.wsConnected = connected;
    const statusEl = document.getElementById('ws-status')!;
    statusEl.textContent = connected ? 'Connected' : 'Disconnected';
    statusEl.className = connected ? 'status-on' : 'status-off';
    log(connected ? 'WebSocket connected' : 'WebSocket disconnected');
  },
);

// ── Connect form ──

const connectForm = document.getElementById('connect-form') as HTMLFormElement;
const connectBtn = document.getElementById('connect-btn') as HTMLButtonElement;
const disconnectBtn = document.getElementById('disconnect-btn') as HTMLButtonElement;

const savedSettings = localStorage.getItem('aksabot-sim-settings');
if (savedSettings) {
  const s = JSON.parse(savedSettings);
  (document.getElementById('backend-url') as HTMLInputElement).value = s.backendUrl ?? '';
  (document.getElementById('email') as HTMLInputElement).value = s.email ?? '';
  (document.getElementById('password') as HTMLInputElement).value = s.password ?? '';
}

connectForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const backendUrl = (document.getElementById('backend-url') as HTMLInputElement).value;
  const email = (document.getElementById('email') as HTMLInputElement).value;
  const password = (document.getElementById('password') as HTMLInputElement).value;

  localStorage.setItem('aksabot-sim-settings', JSON.stringify({ backendUrl, email, password }));

  connectBtn.disabled = true;
  connectBtn.textContent = 'Connecting...';
  try {
    // Init audio player (needs user gesture for AudioContext)
    await audioPlayer.init();
    await audioPlayer.resume();

    await ws.connect(backendUrl, email, password, 'Web Simulator');
    log('Authenticated and connected');
  } catch (err) {
    log(`Connection failed: ${(err as Error).message}`);
  } finally {
    connectBtn.disabled = false;
    connectBtn.textContent = 'Connect';
  }
});

disconnectBtn.addEventListener('click', () => {
  ws.disconnect();
});

// ── Expression picker ──

const exprSelect = document.getElementById('expr-select') as HTMLSelectElement;
Object.keys(Expression)
  .filter((k) => isNaN(Number(k)) && k !== 'COUNT')
  .forEach((name) => {
    const opt = document.createElement('option');
    opt.value = String(Expression[name as keyof typeof Expression]);
    opt.textContent = name;
    exprSelect.appendChild(opt);
  });

exprSelect.addEventListener('change', () => {
  const expr = Number(exprSelect.value) as Expression;
  display.face.setExpression(expr);
  log(`Expression set to ${Expression[expr]}`);
});

// ── Hold to Speak button (mic recording) ──

const speakBtn = document.getElementById('btn-speak')!;
let isRecording = false;

speakBtn.addEventListener('mousedown', async () => {
  if (isRecording) return;
  isRecording = true;
  speakBtn.classList.add('recording');

  // Resume audio context (browser autoplay policy)
  await audioPlayer.resume();

  // Tell backend we're sending PCM audio
  ws.send('audio:start', { format: 'pcm16' });
  display.face.setExpression(Expression.LISTENING);

  try {
    await audioRecorder.start();
    log('Recording started (mic → PCM → backend)');
  } catch (err) {
    log(`Mic error: ${(err as Error).message}`);
    isRecording = false;
    speakBtn.classList.remove('recording');
  }
});

const stopRecording = () => {
  if (!isRecording) return;
  isRecording = false;
  speakBtn.classList.remove('recording');

  audioRecorder.stop();
  ws.send('audio:end');
  log('Recording stopped');
};

speakBtn.addEventListener('mouseup', stopRecording);
speakBtn.addEventListener('mouseleave', stopRecording);

// Touch support
speakBtn.addEventListener('touchstart', (e) => {
  e.preventDefault();
  speakBtn.dispatchEvent(new MouseEvent('mousedown'));
});
speakBtn.addEventListener('touchend', (e) => {
  e.preventDefault();
  stopRecording();
});

// ── Other simulate buttons ──

document.getElementById('btn-arrive')!.addEventListener('click', () => {
  display.face.setExpression(Expression.HAPPY);
  ws.send('presence:arrived');
  log('Presence: arrived');
  setTimeout(() => display.face.setExpression(Expression.IDLE), 3000);
});

document.getElementById('btn-depart')!.addEventListener('click', () => {
  display.face.setExpression(Expression.SAD);
  ws.send('presence:departed');
  log('Presence: departed');
  setTimeout(() => display.face.setExpression(Expression.IDLE), 3000);
});

document.getElementById('btn-dismiss')!.addEventListener('click', () => {
  display.setMode(0); // FACE
  ws.send('proactive:dismiss');
  log('Dismissed reminder');
});

// ── Render loop ──

function frame(): void {
  display.tick(performance.now());
  requestAnimationFrame(frame);
}

requestAnimationFrame(frame);
log('Simulator started — face rendering at 60fps');
