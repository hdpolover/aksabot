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
    _client.setInsecure(); // no SSL cert verification (local network)
    _client.onEvent(onEvent);
    _client.onMessage(::onMessage);

    // Attach device token as Authorization header
    _client.addHeader("Authorization", String("Bearer ") + _token);

    bool ok = _client.connect(_host, _port, "/ws");
    if (!ok) {
        Serial.println("[WS] Connection failed");
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
