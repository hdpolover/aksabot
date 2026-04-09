#include "ws_client.h"
#include "config.h"
#include "state.h"
#include <ArduinoJson.h>
#include <Arduino.h>

using namespace websockets;

static WebsocketsClient client;
static ws_client::JsonCallback jsonCb;
static ws_client::BinaryCallback binaryCb;

static uint32_t reconnectDelay = WS_RECONNECT_BASE_MS;
static unsigned long lastReconnectAttempt = 0;
static bool shouldReconnect = true;

// ── Event handlers ──────────────────────────────────────

static void onMessage(WebsocketsMessage msg) {
    if (msg.isBinary()) {
        if (binaryCb) {
            binaryCb((const uint8_t*)msg.c_str(), msg.length());
        }
        return;
    }

    // Parse JSON text message
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, msg.data());
    if (err) {
        Serial.printf("[WS] JSON parse error: %s\n", err.c_str());
        return;
    }

    const char* event = doc["event"] | "";
    // Serialize data back to string for the callback
    char dataBuf[512];
    if (doc["data"].isNull()) {
        dataBuf[0] = '\0';
    } else {
        serializeJson(doc["data"], dataBuf, sizeof(dataBuf));
    }

    if (jsonCb) {
        jsonCb(event, dataBuf);
    }
}

static void onEvent(WebsocketsEvent event, String data) {
    switch (event) {
        case WebsocketsEvent::ConnectionOpened:
            Serial.println("[WS] Connected");
            appState.wsConnected = true;
            reconnectDelay = WS_RECONNECT_BASE_MS;
            break;

        case WebsocketsEvent::ConnectionClosed:
            Serial.printf("[WS] Disconnected: %s\n", data.c_str());
            appState.wsConnected = false;
            break;

        case WebsocketsEvent::GotPing:
            // Library auto-responds with pong
            break;

        case WebsocketsEvent::GotPong:
            break;
    }
}

// ── Public API ──────────────────────────────────────────

void ws_client::init(JsonCallback onJson, BinaryCallback onBinary) {
    jsonCb = onJson;
    binaryCb = onBinary;

    client.onMessage(onMessage);
    client.onEvent(onEvent);

    // Set device token auth header
    String authHeader = String("DeviceToken ") + DEVICE_TOKEN;
    client.addHeader("Authorization", authHeader.c_str());
}

void ws_client::connect() {
    shouldReconnect = true;
    Serial.printf("[WS] Connecting to %s...\n", BACKEND_WS_URL);
    client.connect(BACKEND_WS_URL);
}

void ws_client::poll() {
    if (client.available()) {
        client.poll();
    }

    // Auto-reconnect with exponential backoff
    if (shouldReconnect && !appState.wsConnected && appState.wifiConnected) {
        unsigned long now = millis();
        if ((now - lastReconnectAttempt) > reconnectDelay) {
            Serial.printf("[WS] Reconnecting (backoff %ums)...\n", reconnectDelay);
            client.connect(BACKEND_WS_URL);
            lastReconnectAttempt = now;
            reconnectDelay = min(reconnectDelay * 2, (uint32_t)WS_RECONNECT_MAX_MS);
        }
    }
}

bool ws_client::isConnected() {
    return appState.wsConnected;
}

void ws_client::sendEvent(const char* event, const char* jsonData) {
    if (!appState.wsConnected) return;

    JsonDocument doc;
    doc["event"] = event;
    if (jsonData && jsonData[0] != '\0') {
        JsonDocument dataDoc;
        deserializeJson(dataDoc, jsonData);
        doc["data"] = dataDoc.as<JsonVariant>();
    }

    char buf[256];
    size_t len = serializeJson(doc, buf, sizeof(buf));
    client.send(buf, len);
    Serial.printf("[WS] Sent: %s\n", buf);
}

void ws_client::sendBinary(const uint8_t* data, size_t len) {
    if (!appState.wsConnected) return;
    client.sendBinary((const char*)data, len);
}

void ws_client::disconnect() {
    shouldReconnect = false;
    client.close();
}
