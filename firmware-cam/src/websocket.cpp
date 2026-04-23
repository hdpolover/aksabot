#include "websocket.h"
#include "credentials.h"
#include <ArduinoWebsockets.h>

using namespace websockets;

static WebsocketsClient _client;
static ws::MessageCallback _onMessage;
static const char* _host;
static uint16_t _port;
static const char* _token;
static unsigned long _lastConnectAttempt = 0;
static bool _connected = false;

static const unsigned long RECONNECT_INTERVAL_MS = 5000;

static void onEvent(WebsocketsEvent event, String data) {
    if (event == WebsocketsEvent::ConnectionOpened) {
        _connected = true;
        Serial.println("[WS] Connected to backend");
    } else if (event == WebsocketsEvent::ConnectionClosed) {
        _connected = false;
        Serial.println("[WS] Disconnected from backend");
    } else if (event == WebsocketsEvent::GotPing) {
        _client.pong();
    }
}

static void onMessage(WebsocketsMessage msg) {
    if (!msg.isText()) return;
    // Parse {"event":"...", "data":...} — minimal JSON parse
    String raw = msg.data();
    int evStart = raw.indexOf("\"event\":\"");
    if (evStart < 0) return;
    evStart += 9;
    int evEnd = raw.indexOf("\"", evStart);
    if (evEnd < 0) return;
    String event = raw.substring(evStart, evEnd);

    int dataStart = raw.indexOf("\"data\":");
    String data = "";
    if (dataStart >= 0) {
        data = raw.substring(dataStart + 7);
        // trim trailing }
        while (data.endsWith("}")) data = data.substring(0, data.length() - 1);
        data.trim();
    }
    _onMessage(event, data);
}

static bool connectToBackend() {
    Serial.printf("[WS] Connecting to %s:%d\n", _host, _port);
    _client.setInsecure(); // skip cert verification (self-signed or Cloudflare)
    _client.onEvent(onEvent);
    _client.onMessage(::onMessage);

    // Pass token as query param — Cloudflare strips Authorization headers on WS upgrade
    // Backend also accepts ?token= (extractDeviceToken checks query params as fallback)
    String wsPath = String("/ws?token=") + _token;
    String url = (_port == 443)
        ? String("wss://") + _host + wsPath
        : String("ws://") + _host + ":" + _port + wsPath;
    Serial.printf("[WS] Connecting via URL: wss://%s/ws?token=%.8s...\n", _host, _token);
    bool ok = _client.connect(url.c_str());
    if (!ok) {
        Serial.printf("[WS] Connection failed (heap=%d)\n", ESP.getFreeHeap());
    }
    return ok;
}

namespace ws {

void init(const char* host, uint16_t port, const char* token, MessageCallback onMessage) {
    _host = host;
    _port = port;
    _token = token;
    _onMessage = onMessage;
    connectToBackend();
}

void loop() {
    if (_client.available()) {
        _client.poll();
    } else if (!_connected) {
        unsigned long now = millis();
        if (now - _lastConnectAttempt > RECONNECT_INTERVAL_MS) {
            _lastConnectAttempt = now;
            connectToBackend();
        }
    }
}

void send(const String& event, const String& data) {
    if (!_connected) return;
    String msg = "{\"event\":\"" + event + "\",\"data\":" + data + "}";
    _client.send(msg);
}

bool connected() {
    return _connected;
}

} // namespace ws
