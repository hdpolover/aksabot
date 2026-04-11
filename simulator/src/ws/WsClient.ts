type EventCallback = (event: string, data: Record<string, unknown>) => void;
type BinaryCallback = (data: ArrayBuffer) => void;
type StatusCallback = (connected: boolean) => void;

export class WsClient {
  private ws: WebSocket | null = null;
  private onEvent: EventCallback;
  private onBinary: BinaryCallback;
  private onStatus: StatusCallback;
  private deviceToken = '';
  private wsUrl = '';
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    onEvent: EventCallback,
    onBinary: BinaryCallback,
    onStatus: StatusCallback,
  ) {
    this.onEvent = onEvent;
    this.onBinary = onBinary;
    this.onStatus = onStatus;
  }

  async connect(backendUrl: string, email: string, password: string, deviceName: string): Promise<void> {
    const httpUrl = backendUrl.replace(/\/+$/, '');
    this.wsUrl = httpUrl.replace(/^http/, 'ws') + '/ws';

    // Check localStorage for saved token
    const storageKey = `aksabot-sim-${httpUrl}`;
    const saved = localStorage.getItem(storageKey);
    if (saved) {
      try {
        const state = JSON.parse(saved);
        this.deviceToken = state.deviceToken;
        this.openSocket();
        return;
      } catch {
        localStorage.removeItem(storageKey);
      }
    }

    // Login
    const loginRes = await this.http(httpUrl, 'POST', '/auth/login', { email, password });
    const accessToken = loginRes.data.accessToken;

    // Try to find existing simulator device
    let deviceToken: string | undefined;
    try {
      const devicesRes = await this.http(httpUrl, 'GET', '/devices', undefined, accessToken as string);
      const devices = devicesRes.data as unknown as Array<{ name: string; deviceToken?: string }>;
      const existing = devices.find((d: { name: string }) => d.name === deviceName);
      if (existing?.deviceToken) {
        deviceToken = existing.deviceToken;
      }
    } catch {
      // ignore — will create new
    }

    if (!deviceToken) {
      const deviceRes = await this.http(httpUrl, 'POST', '/devices', { name: deviceName }, accessToken as string);
      deviceToken = deviceRes.data.deviceToken as string;
    }

    this.deviceToken = deviceToken;
    localStorage.setItem(storageKey, JSON.stringify({ deviceToken }));
    this.openSocket();
  }

  private openSocket(): void {
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.close();
    }

    this.ws = new WebSocket(`${this.wsUrl}?token=${this.deviceToken}`);
    this.ws.binaryType = 'arraybuffer';

    this.ws.onopen = () => {
      this.onStatus(true);
    };

    this.ws.onmessage = (ev) => {
      if (typeof ev.data === 'string') {
        try {
          const msg = JSON.parse(ev.data);
          this.onEvent(msg.event, msg.data ?? {});
        } catch {
          // ignore
        }
      } else if (ev.data instanceof ArrayBuffer) {
        // Binary: raw Opus frame from backend
        this.onBinary(ev.data);
      }
    };

    this.ws.onclose = () => {
      this.onStatus(false);
      this.scheduleReconnect();
    };

    this.ws.onerror = () => {
      // onclose fires after
    };
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (this.deviceToken && this.wsUrl) {
        this.openSocket();
      }
    }, 3000);
  }

  send(event: string, data: Record<string, unknown> = {}): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ event, data }));
    }
  }

  sendBinary(data: ArrayBuffer): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(data);
    }
  }

  disconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.close();
      this.ws = null;
    }
    this.onStatus(false);
  }

  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  private async http(
    base: string,
    method: string,
    endpoint: string,
    body?: Record<string, unknown>,
    token?: string,
  ): Promise<{ data: Record<string, unknown> }> {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const res = await fetch(`${base}${endpoint}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });

    const json = await res.json();
    if (!res.ok) throw new Error(`${res.status} ${method} ${endpoint}: ${JSON.stringify(json)}`);
    return json;
  }
}
