/**
 * WebSocket Simulator — simulates the ESP32 client for end-to-end testing.
 *
 * Usage:
 *   npx ts-node test/ws-simulator.ts                    # interactive mode
 *   npx ts-node test/ws-simulator.ts --audio <file.pcm> # send audio file
 *   npx ts-node test/ws-simulator.ts --setup-only       # register + create device, print token, exit
 *
 * Requires the backend to be running (npm run start:dev) and
 * docker-compose up (PostgreSQL + Redis).
 *
 * On first run, creates a test user + device and saves credentials to
 * test/.ws-simulator-state.json so subsequent runs reuse them.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as readline from 'readline';
import WebSocket from 'ws';

// ── Config ──────────────────────────────────────────────────────

const BASE_URL = process.env.BASE_URL ?? 'http://localhost:4280';
const WS_URL = process.env.WS_URL ?? 'ws://localhost:4280/ws';
const STATE_FILE = path.join(__dirname, '.ws-simulator-state.json');

const TEST_USER = {
  email: 'test@aksabot.local',
  password: 'TestPass123!',
  name: 'Test User',
};

interface SavedState {
  accessToken: string;
  refreshToken: string;
  userId: string;
  deviceId: string;
  deviceToken: string;
}

// ── HTTP helpers ────────────────────────────────────────────────

async function post(
  endpoint: string,
  body: Record<string, any>,
  token?: string,
): Promise<any> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });

  const json = await res.json();
  if (!res.ok) {
    throw new Error(
      `${res.status} ${endpoint}: ${JSON.stringify(json)}`,
    );
  }
  return json;
}

// ── Setup: register user + create device ────────────────────────

async function loadOrCreateState(): Promise<SavedState> {
  // Try loading existing state
  if (fs.existsSync(STATE_FILE)) {
    const saved: SavedState = JSON.parse(
      fs.readFileSync(STATE_FILE, 'utf-8'),
    );
    // Verify token still works by refreshing
    try {
      const refreshRes = await post('/auth/refresh', {
        refreshToken: saved.refreshToken,
      });
      saved.accessToken = refreshRes.data.accessToken;
      saved.refreshToken = refreshRes.data.refreshToken;
      fs.writeFileSync(STATE_FILE, JSON.stringify(saved, null, 2));
      log('info', `Reusing saved state (user: ${saved.userId}, device: ${saved.deviceId})`);
      return saved;
    } catch {
      log('warn', 'Saved state expired, re-creating...');
    }
  }

  // Register or login
  let authRes: any;
  try {
    authRes = await post('/auth/register', TEST_USER);
    log('ok', `Registered user: ${authRes.data.user.email}`);
  } catch {
    authRes = await post('/auth/login', {
      email: TEST_USER.email,
      password: TEST_USER.password,
    });
    log('ok', `Logged in as: ${authRes.data.user.email}`);
  }

  const { accessToken, refreshToken, user } = authRes.data;

  // Create device
  const deviceRes = await post(
    '/devices',
    { name: 'WS Simulator' },
    accessToken,
  );
  const { device, deviceToken } = deviceRes.data;
  log('ok', `Created device: ${device.name} (${device.id})`);

  const state: SavedState = {
    accessToken,
    refreshToken,
    userId: user.id,
    deviceId: device.id,
    deviceToken,
  };

  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  return state;
}

// ── WebSocket client ────────────────────────────────────────────

function connectWebSocket(deviceToken: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL, {
      headers: { Authorization: `DeviceToken ${deviceToken}` },
    });

    ws.on('open', () => {
      log('ok', 'WebSocket connected');
      resolve(ws);
    });

    ws.on('error', (err) => {
      log('error', `WebSocket error: ${err.message}`);
      reject(err);
    });
  });
}

function attachListeners(ws: WebSocket) {
  ws.on('message', (raw: Buffer, isBinary: boolean) => {
    if (isBinary) {
      log('recv', `[binary] ${raw.length} bytes (Opus audio)`);
      return;
    }

    try {
      const msg = JSON.parse(raw.toString());
      const eventName = msg.event;
      const data = msg.data;

      switch (eventName) {
        case 'state:update':
          log('state', data.state);
          break;
        case 'session:start':
          log('recv', `Session started: ${data.sessionId}`);
          break;
        case 'session:end':
          log('recv', `Session ended: ${data.sessionId} (${data.reason})`);
          break;
        case 'transcript:partial':
          log('stt', `(partial) ${data.text}`);
          break;
        case 'transcript:final':
          log('stt', `(final) ${data.text}`);
          break;
        case 'response:start':
          log('recv', `Response started (${data.type})`);
          break;
        case 'response:text':
          log('llm', data.text);
          break;
        case 'response:end':
          log('recv', `Response ended`);
          if (data.fullText) {
            log('llm', `[full] ${data.fullText}`);
          }
          break;
        case 'error':
          log('error', `${data.code}: ${data.message}`);
          break;
        default:
          log('recv', `${eventName}: ${JSON.stringify(data)}`);
      }
    } catch {
      log('recv', `[unparseable] ${raw.toString().slice(0, 200)}`);
    }
  });

  ws.on('close', (code, reason) => {
    log('info', `WebSocket closed: ${code} ${reason.toString()}`);
  });
}

function sendEvent(ws: WebSocket, event: string, data?: any) {
  const msg = JSON.stringify({ event, data });
  ws.send(msg);
  log('send', `${event}${data ? ' ' + JSON.stringify(data) : ''}`);
}

// ── Audio sending ───────────────────────────────────────────────

function sendAudioFile(ws: WebSocket, filePath: string) {
  const absolutePath = path.resolve(filePath);
  if (!fs.existsSync(absolutePath)) {
    log('error', `File not found: ${absolutePath}`);
    return;
  }

  const audioData = fs.readFileSync(absolutePath);
  log('info', `Sending audio file: ${absolutePath} (${audioData.length} bytes)`);

  sendEvent(ws, 'audio:start');

  // Send in chunks (simulate ESP32 streaming at ~20ms Opus frames)
  const CHUNK_SIZE = 160; // ~20ms of Opus at 16kHz
  let offset = 0;
  const interval = setInterval(() => {
    if (offset >= audioData.length) {
      clearInterval(interval);
      sendEvent(ws, 'audio:end');
      return;
    }

    const chunk = audioData.subarray(offset, offset + CHUNK_SIZE);
    ws.send(chunk);
    offset += CHUNK_SIZE;
  }, 20);
}

// ── Interactive REPL ────────────────────────────────────────────

function startRepl(ws: WebSocket) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '\naksabot> ',
  });

  console.log(`
╔═══════════════════════════════════════════════╗
║          Aksabot WebSocket Simulator          ║
╠═══════════════════════════════════════════════╣
║ Commands:                                     ║
║   start          Send audio:start             ║
║   end            Send audio:end               ║
║   interrupt      Send audio:interrupt          ║
║   session:end    End current conversation     ║
║   audio <file>   Send audio file              ║
║   ping           Send WebSocket ping          ║
║   quit           Disconnect and exit          ║
╚═══════════════════════════════════════════════╝
`);

  rl.prompt();

  rl.on('line', (line) => {
    const input = line.trim();
    if (!input) {
      rl.prompt();
      return;
    }

    const [cmd, ...args] = input.split(/\s+/);

    switch (cmd) {
      case 'start':
        sendEvent(ws, 'audio:start');
        break;
      case 'end':
        sendEvent(ws, 'audio:end');
        break;
      case 'interrupt':
        sendEvent(ws, 'audio:interrupt');
        break;
      case 'session:end':
        sendEvent(ws, 'session:end');
        break;
      case 'audio':
        if (!args[0]) {
          log('error', 'Usage: audio <file.pcm>');
        } else {
          sendAudioFile(ws, args[0]);
        }
        break;
      case 'ping':
        ws.ping();
        log('send', 'ping');
        break;
      case 'quit':
      case 'exit':
        ws.close();
        rl.close();
        process.exit(0);
        break;
      default:
        log('warn', `Unknown command: ${cmd}`);
    }

    rl.prompt();
  });

  rl.on('close', () => {
    ws.close();
    process.exit(0);
  });
}

// ── Logging ─────────────────────────────────────────────────────

const COLORS = {
  ok: '\x1b[32m',    // green
  info: '\x1b[36m',  // cyan
  warn: '\x1b[33m',  // yellow
  error: '\x1b[31m', // red
  send: '\x1b[35m',  // magenta
  recv: '\x1b[34m',  // blue
  state: '\x1b[33m', // yellow
  stt: '\x1b[36m',   // cyan
  llm: '\x1b[32m',   // green
  reset: '\x1b[0m',
};

function log(level: keyof typeof COLORS, msg: string) {
  if (level === 'reset') return;
  const color = COLORS[level] ?? COLORS.info;
  const tag = level.toUpperCase().padEnd(5);
  const ts = new Date().toISOString().slice(11, 23);
  console.log(`${color}[${ts}] ${tag}${COLORS.reset} ${msg}`);
}

// ── Main ────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const setupOnly = args.includes('--setup-only');
  const audioFileIdx = args.indexOf('--audio');
  const audioFile = audioFileIdx >= 0 ? args[audioFileIdx + 1] : null;

  try {
    log('info', `Connecting to backend at ${BASE_URL}`);
    const state = await loadOrCreateState();

    if (setupOnly) {
      console.log('\nDevice token for manual testing:');
      console.log(`  ${state.deviceToken}\n`);
      console.log('WebSocket connection:');
      console.log(`  wscat -c ${WS_URL} -H "Authorization: DeviceToken ${state.deviceToken}"\n`);
      return;
    }

    const ws = await connectWebSocket(state.deviceToken);
    attachListeners(ws);

    if (audioFile) {
      // Non-interactive: send audio file and wait for response
      sendAudioFile(ws, audioFile);
      // Wait for response to complete, then exit after 30s timeout
      setTimeout(() => {
        log('info', 'Timeout reached, closing connection');
        ws.close();
        process.exit(0);
      }, 30_000);
    } else {
      // Interactive mode
      startRepl(ws);
    }
  } catch (err: any) {
    log('error', err.message);
    process.exit(1);
  }
}

main();
