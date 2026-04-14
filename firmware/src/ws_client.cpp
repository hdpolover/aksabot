#include "ws_client.h"
#include "ble_manager.h"
#include "config.h"
#include "state.h"
#include "nvs_store.h"
#include <ArduinoJson.h>
#include <Arduino.h>
#include <freertos/semphr.h>
#include <freertos/queue.h>
#include <freertos/idf_additions.h>
#include <mbedtls/platform.h>
#include <esp_heap_caps.h>

// ── mbedTLS PSRAM allocator ─────────────────────────────
// The pre-built Arduino ESP32 libmbedtls.a has 16KB I/O buffers baked in.
// sdkconfig.defaults cannot change them (pre-compiled). With ~48KB free heap
// and fragmentation, a single calloc for the SSL context (~40KB total) fails.
//
// Fix: override mbedtls_calloc/free at runtime. Allocations ≥4KB go to PSRAM
// (8MB free), so the large SSL buffers never touch fragmented internal SRAM.
static void* mbedtls_psram_calloc(size_t count, size_t size) {
    // Route ALL mbedTLS allocations to PSRAM (8MB available).
    // Previous threshold of 4096 still let small structures (<4KB) drain internal SRAM —
    // after ~40s of WS connection, AES allocation fails and the session crashes.
    // With threshold=0 all mbedTLS memory comes from PSRAM, leaving internal SRAM
    // free for DMA, ISR stacks, and NimBLE structures.
    void* p = heap_caps_calloc(count, size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (p) return p;
    // PSRAM failed (extremely unlikely) — fall back to internal heap as last resort
    return heap_caps_calloc(count, size, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
}

static void mbedtls_psram_free(void* ptr) {
    heap_caps_free(ptr);
}

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
static bool everAttempted = false;
static bool shouldReconnect = true;

// Keepalive
// Keepalive: firmware sends pings but does NOT enforce pong timeout.
// The backend has its own heartbeat (10s ping, 20s timeout) which handles
// dead connection detection. Reverse proxies (Traefik) may intercept
// WebSocket pings, preventing pongs from reaching the firmware.
static const uint32_t PING_INTERVAL_MS = 30000;   // ping every 30s (keepalive only)
static uint32_t lastPingMs = 0;
static uint32_t lastPongMs = 0;
static bool pingSent = false;
static const uint32_t PONG_TIMEOUT_MS = 0;         // disabled — rely on backend heartbeat

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
    char dataBuf[1024];
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
    // Don't connect if already connected
    if (appState.wsConnected) {
        return true;
    }

    // Defensively close before attempting a new connection.
    //
    // After an abrupt server-side close (heartbeat timeout while LISTENING and not
    // polling), the static client object retains stale socket state. close() resets
    // ArduinoWebsockets' internal stream pointer; the vTaskDelay lets lwIP fully
    // release the old fd before we open a new socket.
    //
    // setInsecure() is re-asserted defensively (it persists from init() but this
    // is explicit documentation of intent).
    //
    // Do NOT call addHeader() here. _customHeaders is never cleared by close() or
    // connect(), so the Authorization header added in init() persists across all
    // reconnects automatically. Calling addHeader() here duplicates the header on
    // every reconnect — Node.js joins duplicate same-name headers with a comma, so
    // the backend receives "DeviceToken abc, DeviceToken abc", fails token validation,
    // and returns a non-101 HTTP response → "Connect failed" every attempt.
    client.close();
    vTaskDelay(pdMS_TO_TICKS(100));

    if (strncmp(wsUrlBuf, "wss://", 6) == 0) {
        client.setInsecure();
    }

    // Pause BLE presence scanning during SSL handshake.
    // The TLS handshake needs ~40KB of heap. BLE scanning runs concurrently
    // and can consume enough heap to push the allocator below that threshold,
    // causing MBEDTLS_ERR_SSL_ALLOC_FAILED. Pause for the duration of the
    // connect call and resume immediately after regardless of outcome.
    ble_manager::pausePresenceScan();

    everAttempted = true;
    lastConnectAttemptMs = millis();
    Serial.printf("[WS] Connecting to %s...\n", wsUrlBuf);
    Serial.printf("[WS] Free heap: %u, PSRAM: %u\n", ESP.getFreeHeap(), ESP.getFreePsram());
    uint32_t connectStart = millis();
    bool ok = client.connect(wsUrlBuf);
    uint32_t connectMs = millis() - connectStart;
    if (ok) {
        Serial.printf("[WS] Connected! (%ums)\n", connectMs);
    } else {
        Serial.printf("[WS] Connect failed (%ums)\n", connectMs);
    }

    ble_manager::resumePresenceScan();
    return ok;
}

// ── Public API ──────────────────────────────────────────

void ws_client::init(JsonCallback onJson, BinaryCallback onBinary) {
    jsonCb = onJson;
    binaryCb = onBinary;

    // Redirect mbedTLS heap to PSRAM before any SSL context is created.
    // Must be called before the first connect() — cannot be changed mid-session.
    mbedtls_platform_set_calloc_free(mbedtls_psram_calloc, mbedtls_psram_free);
    Serial.println("[WS] mbedTLS allocator → PSRAM (all allocs)");

    wsMutex = xSemaphoreCreateMutex();
    // Allocate the frame queue in PSRAM — 20 × 520 bytes = ~10KB.
    // xQueueCreate uses internal SRAM by default; moving this queue to PSRAM
    // frees critical DMA-accessible internal SRAM for hardware AES operations.
    frameQueue = xQueueCreateWithCaps(WS_FRAME_QUEUE_SIZE, sizeof(WsFrame),
                                      MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);

    client.onMessage(onMessage);
    client.onEvent(onEvent);

    if (!nvs_store::getBackendUrl(wsUrlBuf, sizeof(wsUrlBuf))) {
        strncpy(wsUrlBuf, BACKEND_WS_URL, sizeof(wsUrlBuf) - 1);
    }
    if (!nvs_store::getDeviceToken(tokenBuf, sizeof(tokenBuf))) {
        strncpy(tokenBuf, DEVICE_TOKEN, sizeof(tokenBuf) - 1);
    }

    // Enable SSL for wss:// URLs (skip certificate validation).
    // The ArduinoWebsockets library was patched to call WiFiClientSecure::setInsecure()
    // on ESP32 when no CA cert is set (upstream only did this for ESP8266).
    if (strncmp(wsUrlBuf, "wss://", 6) == 0) {
        client.setInsecure();
        Serial.println("[WS] SSL enabled (insecure mode)");
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

    // Dead connection detection — disabled for WSS through reverse proxy.
    // Traefik intercepts WS pings, so pongs never reach the firmware.
    // The backend's server-side heartbeat handles dead device detection.

    // Auto-reconnect
    if (shouldReconnect && !appState.wsConnected && appState.wifiConnected && everAttempted) {
        if ((now - lastConnectAttemptMs) >= reconnectDelay) {
            // Skip reconnect if heap is too low for SSL.
            // sdkconfig.defaults sets SSL buffers to 4KB each (~12KB total needed).
            // 20KB threshold gives comfortable headroom without false-blocking.
            uint32_t freeHeap = ESP.getFreeHeap();
            if (freeHeap < 20000) {
                Serial.printf("[WS] Skipping reconnect — low heap (%u bytes)\n", freeHeap);
                lastConnectAttemptMs = now;  // don't spam
                xSemaphoreGive(wsMutex);
                return;
            }
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

    if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(500))) {
        client.send(buf, len);
        xSemaphoreGive(wsMutex);
        Serial.printf("[WS] Sent: %s\n", buf);
    } else {
        Serial.printf("[WS] sendEvent timeout — mutex held >500ms (event: %s)\n", event);
    }
}

void ws_client::sendBinary(const uint8_t* data, size_t len) {
    if (!appState.wsConnected) return;

    // Use a short mutex timeout (3ms) to prevent a data race with sendEvent()
    // during the LISTENING→THINKING transition.
    //
    // The comment that said "no mutex needed" was wrong: while poll() does skip
    // during LISTENING, sendEvent("audio:end") runs on Core 1 WITH the mutex at
    // the same instant the audio task (Core 0) calls sendBinary() for the last
    // frame. Both cores access `client` simultaneously, corrupting the WebSocket
    // TCP stream and causing the backend to silently drop the audio session.
    //
    // 3ms timeout: during normal LISTENING no one else holds the mutex, so this
    // is always free (no contention, no frame drops). On the brief LISTENING→THINKING
    // transition, if sendEvent holds the mutex we drop this last frame — that's fine.
    if (!xSemaphoreTake(wsMutex, pdMS_TO_TICKS(3))) {
        // Mutex held by sendEvent — last frame during transition, safe to drop.
        return;
    }
    client.sendBinary((const char*)data, len);
    xSemaphoreGive(wsMutex);

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

void ws_client::reconnectWithToken() {
    if (!xSemaphoreTake(wsMutex, pdMS_TO_TICKS(3000))) {
        Serial.println("[WS] reconnectWithToken: mutex timeout");
        return;
    }

    // Close any existing connection
    if (appState.wsConnected || client.available()) {
        client.close();
        appState.wsConnected = false;
    }

    // Re-read backend URL and token from NVS
    if (!nvs_store::getBackendUrl(wsUrlBuf, sizeof(wsUrlBuf))) {
        strncpy(wsUrlBuf, BACKEND_WS_URL, sizeof(wsUrlBuf) - 1);
        wsUrlBuf[sizeof(wsUrlBuf) - 1] = '\0';
    }
    if (!nvs_store::getDeviceToken(tokenBuf, sizeof(tokenBuf))) {
        strncpy(tokenBuf, DEVICE_TOKEN, sizeof(tokenBuf) - 1);
        tokenBuf[sizeof(tokenBuf) - 1] = '\0';
    }

    // Enable SSL for wss:// URLs
    if (strncmp(wsUrlBuf, "wss://", 6) == 0) {
        client.setInsecure();
    }

    // Replace the Authorization header with the new token.
    // clearHeaders() is required before addHeader() — _customHeaders accumulates
    // entries and is never auto-cleared, so without it we'd send both the old and
    // new token, which causes Node.js to join them with a comma and fail auth.
    client.clearHeaders();
    {
        String authHeader = String("DeviceToken ") + tokenBuf;
        client.addHeader("Authorization", authHeader.c_str());
    }

    // Reset backoff so reconnect happens immediately
    everAttempted = false;
    lastConnectAttemptMs = 0;
    shouldReconnect = true;
    reconnectDelay = WS_RECONNECT_BASE_MS;

    Serial.printf("[WS] Reconnecting with new token to %s...\n", wsUrlBuf);
    doConnect();

    xSemaphoreGive(wsMutex);
}
