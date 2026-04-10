#include "wifi_manager.h"
#include "config.h"
#include "state.h"
#include "nvs_store.h"
#include <WiFi.h>
#include <Arduino.h>

static uint32_t reconnectDelay = WIFI_RECONNECT_BASE_MS;
static unsigned long lastReconnectAttempt = 0;

// Resolved credentials (NVS or compile-time fallback)
static char ssidBuf[64];
static char passBuf[128];

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
