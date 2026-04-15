/**
 * ESP32 Simulator — keeps a device "online" for Flutter app testing.
 *
 * Usage:
 *   npm run esp:sim           # uses saved state or creates new device
 *   npm run esp:sim -- --new  # force create a new device
 *
 * The simulator:
 *  1. Registers/logs in as the test user
 *  2. Creates a device (or reuses existing)
 *  3. Connects via WebSocket with the device token
 *  4. Sends periodic pings to stay alive
 *  5. Prints the device token so you can use it in the Flutter app's "Add via Wi-Fi" flow
 *
 * The device will show as "Online" in the app as long as this script is running.
 */

import * as fs from 'fs';
import * as path from 'path';
import WebSocket from 'ws';

const BASE_URL = process.env.BASE_URL ?? 'http://localhost:4280';
const WS_URL = process.env.WS_URL ?? 'ws://localhost:4280/ws';
const STATE_FILE = path.join(__dirname, '.esp-simulator-state.json');
const FORCE_NEW = process.argv.includes('--new');

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
  deviceName: string;
}

// ── Helpers ────────────────────────────────────────────────────

function log(type: string, msg: string) {
  const colors: Record<string, string> = {
    ok: '\x1b[32m✓\x1b[0m',
    info: '\x1b[36mℹ\x1b[0m',
    warn: '\x1b[33m⚠\x1b[0m',
    error: '\x1b[31m✗\x1b[0m',
    ws: '\x1b[35m⇄\x1b[0m',
  };
  console.log(`${colors[type] ?? '•'} ${msg}`);
}

async function http(
  method: string,
  endpoint: string,
  body?: Record<string, any>,
  token?: string,
): Promise<any> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (res.status === 204) return null;
  const json = await res.json();
  if (!res.ok) {
    throw new Error(
      `${res.status} ${method} ${endpoint}: ${JSON.stringify(json)}`,
    );
  }
  return json;
}

// ── Setup ──────────────────────────────────────────────────────

async function setup(): Promise<SavedState> {
  // Try loading existing state
  if (!FORCE_NEW && fs.existsSync(STATE_FILE)) {
    const saved: SavedState = JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8'));
    try {
      const refreshRes = await http('POST', '/auth/refresh', {
        refreshToken: saved.refreshToken,
      });
      saved.accessToken = refreshRes.data.accessToken;
      saved.refreshToken = refreshRes.data.refreshToken;
      fs.writeFileSync(STATE_FILE, JSON.stringify(saved, null, 2));
      log('info', `Reusing device: ${saved.deviceName} (${saved.deviceId})`);
      return saved;
    } catch {
      log('warn', 'Saved state expired, re-creating...');
    }
  }

  // Register or login
  let authRes: any;
  try {
    authRes = await http('POST', '/auth/register', TEST_USER);
    log('ok', `Registered user: ${authRes.data.user.email}`);
  } catch {
    authRes = await http('POST', '/auth/login', {
      email: TEST_USER.email,
      password: TEST_USER.password,
    });
    log('ok', `Logged in as: ${authRes.data.user.email}`);
  }

  const { accessToken, refreshToken, user } = authRes.data;

  // Create device
  const deviceName = `ESP Simulator ${new Date().toLocaleTimeString()}`;
  const deviceRes = await http(
    'POST',
    '/devices',
    { name: deviceName },
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
    deviceName: device.name,
  };

  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  return state;
}

// ── WebSocket connection ───────────────────────────────────────

function connect(state: SavedState) {
  const ws = new WebSocket(WS_URL, {
    headers: { Authorization: `DeviceToken ${state.deviceToken}` },
  });

  ws.on('open', () => {
    log('ok', 'WebSocket connected — device is now ONLINE');
    log('info', '');
    log('info', '╔══════════════════════════════════════════════════╗');
    log('info', '║  Device is online! The Flutter app should show  ║');
    log('info', '║  the green dot. Press Ctrl+C to disconnect.     ║');
    log('info', '╠══════════════════════════════════════════════════╣');
    log('info', `║  Device ID:    ${state.deviceId}  ║`);
    log('info', `║  Device Token: ${state.deviceToken}  ║`);
    log('info', `║  Device Name:  ${state.deviceName.padEnd(35)}║`);
    log('info', '╚══════════════════════════════════════════════════╝');
    log('info', '');
    log(
      'info',
      'Use the Device Token above in the app\'s "Add via Wi-Fi" flow.',
    );

    // Keepalive ping every 30 seconds
    const interval = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    }, 30_000);

    ws.on('close', () => {
      clearInterval(interval);
      log('warn', 'WebSocket disconnected — device is now OFFLINE');
      log('info', 'Reconnecting in 3s...');
      setTimeout(() => connect(state), 3000);
    });
  });

  ws.on('message', (raw: Buffer | string) => {
    try {
      const msg = JSON.parse(raw.toString());
      log(
        'ws',
        `← ${msg.event}: ${JSON.stringify(msg.data ?? {}).slice(0, 100)}`,
      );

      // Auto-respond to proactive events with acknowledgment
      if (msg.event?.startsWith('proactive:')) {
        ws.send(
          JSON.stringify({
            event: 'proactive:ack',
            data: { event: msg.event },
          }),
        );
      }
    } catch {
      log('ws', `← (binary ${(raw as Buffer).length} bytes)`);
    }
  });

  ws.on('error', (err) => {
    log('error', `WebSocket error: ${err.message}`);
  });
}

// ── Main ───────────────────────────────────────────────────────

async function main() {
  log('info', 'ESP32 Simulator — keeps a device online for testing');
  log('info', `Backend: ${BASE_URL}`);
  log('info', '');

  try {
    const state = await setup();
    connect(state);
  } catch (err: any) {
    log('error', `Setup failed: ${err.message}`);
    log(
      'info',
      'Is the backend running? (npm run start:dev + docker-compose up)',
    );
    process.exit(1);
  }
}

main();
