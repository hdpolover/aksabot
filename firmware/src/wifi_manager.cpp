#include "wifi_manager.h"
#include "config.h"
#include "state.h"
#include "nvs_store.h"
#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <Arduino.h>

static uint32_t reconnectDelay = WIFI_RECONNECT_BASE_MS;
static unsigned long lastReconnectAttempt = 0;

// Set to true by the DISCONNECTED event. Cleared when we call begin().
static volatile bool retryPending = false;

// Timestamp of the most recent WiFi.begin() call (from any code path).
// Guards against double-begin: WiFi.disconnect() inside reconnect() fires
// ARDUINO_EVENT_WIFI_STA_DISCONNECTED asynchronously via the ESP-IDF event
// queue — AFTER reconnect() has already called begin().  That async event
// sets retryPending=true and can cause waitForConnection()/tick() to call
// begin() a second time while the first attempt is still in flight, producing
// ESP_ERR_WIFI_CONN (0x3007).  By refusing to begin() within MIN_BEGIN_GAP_MS
// of the last call, we prevent this regardless of event timing.
static unsigned long lastBeginMs = 0;
static const uint32_t MIN_BEGIN_GAP_MS = 3000;

// Resolved credentials (NVS or compile-time fallback)
static char ssidBuf[64];
static char passBuf[128];

// ── SoftAP state ──────────────────────────────────────────────
static WebServer* apServer = nullptr;
static volatile bool apProvisioned = false;
static bool apActive = false;

static void onWiFiEvent(WiFiEvent_t event) {
    switch (event) {
        case ARDUINO_EVENT_WIFI_STA_GOT_IP:
            Serial.printf("[WiFi] Connected — IP: %s\n", WiFi.localIP().toString().c_str());
            appState.wifiConnected = true;
            reconnectDelay = WIFI_RECONNECT_BASE_MS;  // reset backoff
            retryPending = false;
            // Override DHCP-provided DNS with public resolvers.
            // Must be done here (after GOT_IP) — DHCP runs between begin() and
            // GOT_IP and overwrites any setDNS() called before that point.
            // Some hotspots/corporate networks advertise DNS servers that block
            // external hostnames. Primary: Cloudflare, fallback: Google.
            WiFi.setDNS(IPAddress(1, 1, 1, 1), IPAddress(8, 8, 8, 8));
            Serial.println("[WiFi] DNS set: 1.1.1.1 / 8.8.8.8");
            break;

        case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
            Serial.println("[WiFi] Disconnected");
            appState.wifiConnected = false;
            // Record when the disconnect occurred so backoff starts from here.
            // We mark retry pending here (inside the driver event) rather than
            // from a timer, so we only ever call begin() AFTER the driver has
            // confirmed it stopped — never on top of an in-progress attempt.
            lastReconnectAttempt = millis();
            retryPending = true;
            break;

        default:
            break;
    }
}

void wifi_manager::init() {
    WiFi.mode(WIFI_STA);
    WiFi.onEvent(onWiFiEvent);
    WiFi.setAutoReconnect(false);  // we drive all reconnection via tick() / waitForConnection()

    // Try NVS credentials first, fall back to compile-time constants
    if (nvs_store::hasWifiCredentials() &&
        nvs_store::getWifiSsid(ssidBuf, sizeof(ssidBuf)) &&
        nvs_store::getWifiPassword(passBuf, sizeof(passBuf))) {
        Serial.printf("[WiFi] Using provisioned credentials for '%s'\n", ssidBuf);
    } else {
        strncpy(ssidBuf, WIFI_SSID, sizeof(ssidBuf) - 1);
        strncpy(passBuf, WIFI_PASS, sizeof(passBuf) - 1);
        Serial.printf("[WiFi] Using compile-time credentials for '%s'\n", ssidBuf);
    }

    lastBeginMs = millis();
    WiFi.begin(ssidBuf, passBuf);
}

bool wifi_manager::isConnected() {
    return appState.wifiConnected;
}

bool wifi_manager::waitForConnection(uint32_t timeout_ms) {
    unsigned long start = millis();
    while (!appState.wifiConnected) {
        if (timeout_ms > 0 && (millis() - start) > timeout_ms) {
            return false;
        }

        // Only retry after the DISCONNECTED event has fired (retryPending=true),
        // meaning the driver has actually stopped its previous attempt.
        // This avoids calling begin() on top of an in-progress connection which
        // causes ESP_ERR_WIFI_CONN (0x3007).
        if (retryPending &&
            (millis() - lastReconnectAttempt) >= reconnectDelay &&
            (millis() - lastBeginMs) >= MIN_BEGIN_GAP_MS) {
            retryPending = false;
            Serial.printf("[WiFi] Reconnecting (backoff %ums)...\n", reconnectDelay);
            reconnectDelay = min(reconnectDelay * 2, (uint32_t)WIFI_RECONNECT_MAX_MS);
            lastBeginMs = millis();
            WiFi.begin(ssidBuf, passBuf);
        }

        vTaskDelay(pdMS_TO_TICKS(100));
    }
    return true;
}

void wifi_manager::reconnect(const char* ssid, const char* password) {
    strncpy(ssidBuf, ssid, sizeof(ssidBuf) - 1);
    ssidBuf[sizeof(ssidBuf) - 1] = '\0';
    strncpy(passBuf, password, sizeof(passBuf) - 1);
    passBuf[sizeof(passBuf) - 1] = '\0';

    Serial.printf("[WiFi] Reconnecting with new credentials for '%s'\n", ssidBuf);
    WiFi.disconnect();
    reconnectDelay = WIFI_RECONNECT_BASE_MS;
    lastBeginMs = millis();  // set BEFORE begin() so MIN_BEGIN_GAP_MS guard is in place
    WiFi.begin(ssidBuf, passBuf);
    // Note: WiFi.disconnect() queues ARDUINO_EVENT_WIFI_STA_DISCONNECTED which
    // fires asynchronously and sets retryPending=true — AFTER this function
    // returns.  The lastBeginMs guard in waitForConnection()/tick() prevents a
    // second begin() from being called within MIN_BEGIN_GAP_MS regardless.
}

// ── SoftAP provisioning ───────────────────────────────────────

void wifi_manager::startAP(const char* apName) {
    if (apActive) {
        Serial.println("[WiFi AP] Already active — ignoring startAP()");
        return;
    }

    // AP+STA so BLE can coexist and we can switch to STA without re-init
    WiFi.mode(WIFI_AP);
    bool apOk = WiFi.softAP(apName);  // open network — no password
    Serial.printf("[WiFi] softAP result: %s\n", apOk ? "OK" : "FAILED");
    delay(100);  // let AP stabilize
    // onWiFiEvent is already registered in init(); no duplicate registration here

    Serial.printf("[WiFi] SoftAP '%s' started — IP: %s\n",
                  apName, WiFi.softAPIP().toString().c_str());

    apServer = new WebServer(80);
    apProvisioned = false;

    // POST /provision — accepts JSON body {ssid, password}
    apServer->on("/provision", HTTP_POST, []() {
        const String body = apServer->arg("plain");

        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, body);
        if (err) {
            apServer->send(400, "application/json",
                           "{\"error\":\"invalid JSON\"}");
            Serial.println("[WiFi AP] /provision — bad JSON");
            return;
        }

        const char* ssid     = doc["ssid"]     | (const char*)nullptr;
        const char* password = doc["password"] | "";

        if (!ssid || strlen(ssid) == 0) {
            apServer->send(400, "application/json",
                           "{\"error\":\"ssid required\"}");
            return;
        }

        nvs_store::setWifiSsid(ssid);
        nvs_store::setWifiPassword(password);
        apProvisioned = true;

        apServer->send(200, "application/json", "{\"ok\":true}");
        Serial.printf("[WiFi AP] /provision — credentials received: %s\n", ssid);
    });

    // GET /status — lets the app poll connection state
    apServer->on("/status", HTTP_GET, []() {
        JsonDocument doc;
        doc["provisioned"] = (bool)apProvisioned;
        doc["wifiConnected"] = appState.wifiConnected;
        String out;
        serializeJson(doc, out);
        apServer->send(200, "application/json", out);
    });

    apServer->onNotFound([]() {
        apServer->send(404, "application/json", "{\"error\":\"not found\"}");
    });

    apServer->begin();
    apActive = true;
    Serial.println("[WiFi AP] HTTP server started on port 80");
}

void wifi_manager::stopAP() {
    if (!apActive) return;

    if (apServer) {
        apServer->stop();
        delete apServer;
        apServer = nullptr;
    }

    WiFi.softAPdisconnect(true);
    apActive = false;
    Serial.println("[WiFi AP] Stopped");
}

bool wifi_manager::isAPProvisioned() {
    return apProvisioned;
}

void wifi_manager::tickAP() {
    if (apActive && apServer) {
        apServer->handleClient();
    }
}

void wifi_manager::tick() {
    if (apActive) return;
    if (appState.wifiConnected) return;

    // Only retry after the DISCONNECTED event fired (retryPending=true), meaning
    // the driver has actually stopped.  This is the same guard used during boot
    // in waitForConnection() — it prevents calling begin() on top of an
    // in-progress attempt which causes ESP_ERR_WIFI_CONN.
    if (!retryPending) return;
    if ((millis() - lastReconnectAttempt) < reconnectDelay) return;
    if ((millis() - lastBeginMs) < MIN_BEGIN_GAP_MS) return;

    retryPending = false;
    Serial.printf("[WiFi] Retry (backoff %ums)...\n", reconnectDelay);
    reconnectDelay = min(reconnectDelay * 2, (uint32_t)WIFI_RECONNECT_MAX_MS);
    lastBeginMs = millis();
    WiFi.begin(ssidBuf, passBuf);
}
