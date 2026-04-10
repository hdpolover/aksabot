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
            break;

        case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
            Serial.println("[WiFi] Disconnected");
            appState.wifiConnected = false;
            break;

        default:
            break;
    }
}

void wifi_manager::init() {
    WiFi.mode(WIFI_STA);
    WiFi.onEvent(onWiFiEvent);
    WiFi.setAutoReconnect(false);  // we handle reconnect manually for backoff

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

        // Reconnect with exponential backoff
        if (!WiFi.isConnected() && (millis() - lastReconnectAttempt) > reconnectDelay) {
            Serial.printf("[WiFi] Reconnecting (backoff %ums)...\n", reconnectDelay);
            WiFi.disconnect();
            WiFi.begin(ssidBuf, passBuf);
            lastReconnectAttempt = millis();

            // Exponential backoff with cap
            reconnectDelay = min(reconnectDelay * 2, (uint32_t)WIFI_RECONNECT_MAX_MS);
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
    WiFi.begin(ssidBuf, passBuf);
}

// ── SoftAP provisioning ───────────────────────────────────────

void wifi_manager::startAP(const char* apName) {
    if (apActive) {
        Serial.println("[WiFi AP] Already active — ignoring startAP()");
        return;
    }

    // AP+STA so BLE can coexist and we can switch to STA without re-init
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(apName, "");  // open network — no password needed for setup
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
