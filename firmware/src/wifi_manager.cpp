#include "wifi_manager.h"
#include "config.h"
#include "state.h"
#include <WiFi.h>
#include <Arduino.h>

static uint32_t reconnectDelay = WIFI_RECONNECT_BASE_MS;
static unsigned long lastReconnectAttempt = 0;

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

    Serial.printf("[WiFi] Connecting to %s...\n", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
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
            WiFi.begin(WIFI_SSID, WIFI_PASS);
            lastReconnectAttempt = millis();

            // Exponential backoff with cap
            reconnectDelay = min(reconnectDelay * 2, (uint32_t)WIFI_RECONNECT_MAX_MS);
        }

        vTaskDelay(pdMS_TO_TICKS(100));
    }
    return true;
}
