#include "ws_client.h"
#include "config.h"
#include "state.h"
#include "nvs_store.h"
#include <ArduinoJson.h>
#include <Arduino.h>
#include <freertos/semphr.h>
#include <freertos/queue.h>

using namespace websockets;

// Mutex: protects all WebsocketsClient operations.
static SemaphoreHandle_t wsMutex = nullptr;

// ── Binary frame queue (audio task → WS poll task) ─────
// Audio task enqueues frames lock-free; poll task dequeues
// and sends while it already holds the mutex. No contention.
struct WsFrame {
    uint8_t data[OPUS_MAX_FRAME_BYTES];
    size_t len;
};
static const size_t WS_FRAME_QUEUE_SIZE = 20;  // ~400ms at 20ms/frame
static QueueHandle_t frameQueue = nullptr;

static WebsocketsClient client;
static ws_client::JsonCallback jsonCb;
static ws_client::BinaryCallback binaryCb;

static uint32_t reconnectDelay = WS_RECONNECT_BASE_MS;
static uint32_t lastConnectAttemptMs = 0;
static bool everAttempted = false;    // First attempt always allowed
static const uint32_t MIN_CONNECT_INTERVAL_MS = 5000;
static bool shouldReconnect = true;

// Keepalive
static const uint32_t PING_INTERVAL_MS = 20000;
static uint32_t lastPingMs = 0;
static uint32_t lastPongMs = 0;
static bool pingSent = false;
static const uint32_t PONG_TIMEOUT_MS = 30000;

// Resolved from NVS or compile-time fallback
static char wsUrlBuf[256];
static char tokenBuf[128];

// ── Event handlers ──────────────────────────────────────

static void onMessage(WebsocketsMessage msg) {
    if (msg.isBinary()) {
        if (binaryCb) {
            binaryCb((const uint8_t*)msg.c_str(), msg.length());
        }
        return;
    }

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, msg.data());
    if (err) {
        Serial.printf("[WS] JSON parse error: %s\n", err.c_str());
        return;
    }

    const char* event = doc["event"] | "";
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
            lastPingMs = millis();
            lastPongMs = millis();
            pingSent = false;
            break;

        case WebsocketsEvent::ConnectionClosed:
            Serial.printf("[WS] Disconnected: %s\n", data.c_str());
            appState.wsConnected = false;
            reconnectDelay = WS_RECONNECT_BASE_MS;  // Reset backoff for fast reconnect
            break;

        case WebsocketsEvent::GotPing:
            break;

        case WebsocketsEvent::GotPong:
            lastPongMs = millis();
            break;
    }
}

// ── Internal connect (always called under mutex) ────────

static bool doConnect() {
    uint32_t now = millis();
    // Enforce minimum interval between connect attempts (skip for first attempt)
    if (everAttempted && (now - lastConnectAttemptMs) < MIN_CONNECT_INTERVAL_MS) {
        return false;
    }
    // Don't connect if already connected
    if (appState.wsConnected) {
        return true;
    }

    everAttempted = true;
    lastConnectAttemptMs = now;
    Serial.printf("[WS] Connecting to %s...\n", wsUrlBuf);
    bool ok = client.connect(wsUrlBuf);
    if (!ok) {
        Serial.println("[WS] Connect failed");
    }
    return ok;
}

// ── Public API ──────────────────────────────────────────

void ws_client::init(JsonCallback onJson, BinaryCallback onBinary) {
    jsonCb = onJson;
    binaryCb = onBinary;

    wsMutex = xSemaphoreCreateMutex();
    frameQueue = xQueueCreate(WS_FRAME_QUEUE_SIZE, sizeof(WsFrame));

    client.onMessage(onMessage);
    client.onEvent(onEvent);

    if (!nvs_store::getBackendUrl(wsUrlBuf, sizeof(wsUrlBuf))) {
        strncpy(wsUrlBuf, BACKEND_WS_URL, sizeof(wsUrlBuf) - 1);
    }
    if (!nvs_store::getDeviceToken(tokenBuf, sizeof(tokenBuf))) {
        strncpy(tokenBuf, DEVICE_TOKEN, sizeof(tokenBuf) - 1);
    }

    String authHeader = String("DeviceToken ") + tokenBuf;
    client.addHeader("Authorization", authHeader.c_str());
}

void ws_client::connect() {
    if (appState.wsConnected) return;
    shouldReconnect = true;
    if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(3000))) {
        doConnect();
        xSemaphoreGive(wsMutex);
    }
}

void ws_client::poll() {
    // During recording, skip ALL poll operations — the audio task needs
    // the mutex exclusively for streaming binary frames at 50fps.
    // Keepalive and incoming messages can wait a few seconds.
    if (appState.botState == BotState::LISTENING) {
        return;
    }

    if (!xSemaphoreTake(wsMutex, pdMS_TO_TICKS(50))) return;

    uint32_t now = millis();

    // Process incoming messages
    if (client.available()) {
        client.poll();
    }

    // Keepalive ping
    if (appState.wsConnected && (now - lastPingMs) >= PING_INTERVAL_MS) {
        client.ping();
        lastPingMs = now;
        pingSent = true;
    }

    // Dead connection detection
    if (appState.wsConnected && pingSent && (now - lastPongMs) >= PONG_TIMEOUT_MS) {
        Serial.println("[WS] Pong timeout — closing dead connection");
        client.close();
        appState.wsConnected = false;
        pingSent = false;
    }

    // Auto-reconnect
    if (shouldReconnect && !appState.wsConnected && appState.wifiConnected && everAttempted) {
        if ((now - lastConnectAttemptMs) >= reconnectDelay) {
            Serial.printf("[WS] Reconnecting (backoff %ums)...\n", reconnectDelay);
            if (doConnect()) {
                // success
            } else {
                reconnectDelay = min(reconnectDelay * 2, (uint32_t)WS_RECONNECT_MAX_MS);
            }
        }
    }

    xSemaphoreGive(wsMutex);
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

    if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(100))) {
        client.send(buf, len);
        xSemaphoreGive(wsMutex);
        Serial.printf("[WS] Sent: %s\n", buf);
    }
}

void ws_client::sendBinary(const uint8_t* data, size_t len) {
    if (!appState.wsConnected) return;

    // No mutex needed: during LISTENING (when this is called), poll()
    // returns early so there's no concurrent access to the client.
    client.sendBinary((const char*)data, len);

    static uint32_t frameCount = 0;
    static uint32_t lastLogMs = 0;
    frameCount++;
    uint32_t now = millis();
    if ((now - lastLogMs) >= 2000) {
        Serial.printf("[WS] Sent %u binary frames\n", frameCount);
        lastLogMs = now;
    }
}

void ws_client::waitForPollIdle(uint32_t timeoutMs) {
    // Take and immediately release the mutex — this blocks until
    // poll() finishes its current cycle and releases it.
    if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(timeoutMs))) {
        xSemaphoreGive(wsMutex);
        Serial.println("[WS] Poll idle — safe to send binary");
    } else {
        Serial.println("[WS] Warning: poll did not release mutex in time");
    }
}

void ws_client::disconnect() {
    shouldReconnect = false;
    if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(1000))) {
        client.close();
        xSemaphoreGive(wsMutex);
    }
}
