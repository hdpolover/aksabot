#include "wifi_provision.h"
#include "nvs_store.h"
#include "wifi_manager.h"
#include "state.h"
#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <Arduino.h>
#include <freertos/semphr.h>

#define FIRMWARE_VERSION "1.0.0"

static WebServer server(80);
static SemaphoreHandle_t provSem = nullptr;
static volatile bool provisioned = false;
static char apNameBuf[32] = {};

// ── HTTP Handlers ───────────────────────────────────────

static void handleRoot() {
    JsonDocument doc;
    doc["name"] = "Aksabot";
    doc["version"] = FIRMWARE_VERSION;
    doc["mac"] = WiFi.macAddress();
    doc["provisioned"] = nvs_store::hasWifiCredentials();

    char buf[256];
    serializeJson(doc, buf, sizeof(buf));

    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", buf);
}

static void handleProvision() {
    // Handle CORS preflight
    if (server.method() == HTTP_OPTIONS) {
        server.sendHeader("Access-Control-Allow-Origin", "*");
        server.sendHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
        server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
        server.send(204);
        return;
    }

    if (!server.hasArg("plain")) {
        server.send(400, "application/json", "{\"error\":\"No body\"}");
        return;
    }

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, server.arg("plain"));
    if (err) {
        server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
        return;
    }

    const char* ssid = doc["ssid"] | "";
    const char* password = doc["password"] | "";
    const char* token = doc["deviceToken"] | "";
    const char* backendUrl = doc["backendUrl"] | "";

    if (strlen(ssid) == 0) {
        server.send(400, "application/json", "{\"error\":\"ssid is required\"}");
        return;
    }

    // Save to NVS
    nvs_store::setWifiSsid(ssid);
    nvs_store::setWifiPassword(password);
    Serial.printf("[Provision] WiFi credentials saved: %s\n", ssid);

    if (strlen(token) > 0) {
        nvs_store::setDeviceToken(token);
        Serial.printf("[Provision] Device token saved (%d chars)\n", strlen(token));
    }

    if (strlen(backendUrl) > 0) {
        nvs_store::setBackendUrl(backendUrl);
        Serial.printf("[Provision] Backend URL saved: %s\n", backendUrl);
    }

    // Respond with success
    JsonDocument resp;
    resp["success"] = true;
    resp["message"] = "Credentials saved. Device will connect to WiFi.";

    char respBuf[256];
    serializeJson(resp, respBuf, sizeof(respBuf));
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", respBuf);

    // Signal provisioning complete
    provisioned = true;
    if (provSem) {
        xSemaphoreGive(provSem);
    }

    Serial.println("[Provision] Provisioning complete — will switch to STA mode");
}

static void handleStatus() {
    JsonDocument doc;
    doc["provisioned"] = provisioned;
    doc["wifiConnected"] = appState.wifiConnected;
    doc["wsConnected"] = appState.wsConnected;

    char buf[128];
    serializeJson(doc, buf, sizeof(buf));
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", buf);
}

static void handleNotFound() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(404, "application/json", "{\"error\":\"Not found\"}");
}

// ── Captive portal handler ──────────────────────────────

static void handleCaptivePortal() {
    // Redirect all unknown requests to the root
    // This makes phones show "Sign in to network" popup
    String html = "<!DOCTYPE html><html><head>";
    html += "<meta name='viewport' content='width=device-width,initial-scale=1'>";
    html += "<title>Aksabot Setup</title>";
    html += "<style>";
    html += "body{font-family:sans-serif;text-align:center;padding:20px;background:#111;color:#fff}";
    html += "h1{color:#0ff}";
    html += ".info{background:#222;padding:16px;border-radius:8px;margin:16px 0}";
    html += "code{background:#333;padding:2px 8px;border-radius:4px;color:#0ff}";
    html += "</style></head><body>";
    html += "<h1>Aksabot Setup</h1>";
    html += "<div class='info'>";
    html += "<p>Use the <b>Aksabot</b> app to complete setup.</p>";
    html += "<p>API endpoint: <code>http://";
    html += WiFi.softAPIP().toString();
    html += "</code></p>";
    html += "</div>";
    html += "<div class='info'>";
    html += "<p>Or send a POST to <code>/provision</code> with:</p>";
    html += "<pre style='text-align:left;font-size:12px'>{\"ssid\":\"...\",\"password\":\"...\",\"deviceToken\":\"...\",\"backendUrl\":\"...\"}</pre>";
    html += "</div>";
    html += "</body></html>";

    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "text/html", html);
}

// ── Server task (runs in background) ────────────────────

static TaskHandle_t serverTask = nullptr;

static void serverLoop(void* param) {
    for (;;) {
        server.handleClient();
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

// ── Public API ──────────────────────────────────────────

void wifi_provision::start(const char* apName, const char* apPassword) {
    provSem = xSemaphoreCreateBinary();
    provisioned = false;
    strncpy(apNameBuf, apName, sizeof(apNameBuf) - 1);

    // Start AP
    WiFi.mode(WIFI_AP);
    if (strlen(apPassword) > 0) {
        WiFi.softAP(apName, apPassword);
    } else {
        WiFi.softAP(apName);
    }

    Serial.printf("[Provision] AP started: %s (IP: %s)\n",
                  apName, WiFi.softAPIP().toString().c_str());

    // Set up HTTP routes
    server.on("/", HTTP_GET, handleCaptivePortal);
    server.on("/api", HTTP_GET, handleRoot);
    server.on("/provision", HTTP_POST, handleProvision);
    server.on("/provision", HTTP_OPTIONS, handleProvision);  // CORS preflight
    server.on("/status", HTTP_GET, handleStatus);
    server.onNotFound(handleCaptivePortal);  // Captive portal for all other requests

    server.begin();
    Serial.println("[Provision] HTTP server started on port 80");

    // Run server in background task
    xTaskCreatePinnedToCore(serverLoop, "http_srv", 4096, nullptr, 2, &serverTask, 1);
}

void wifi_provision::stop() {
    if (serverTask) {
        vTaskDelete(serverTask);
        serverTask = nullptr;
    }
    server.stop();
    WiFi.softAPdisconnect(true);
    Serial.println("[Provision] AP + HTTP server stopped");
}

bool wifi_provision::isProvisioned() {
    return provisioned;
}

bool wifi_provision::waitForProvisioning(uint32_t timeoutMs) {
    TickType_t ticks = (timeoutMs == 0) ? portMAX_DELAY : pdMS_TO_TICKS(timeoutMs);

    Serial.println("[Provision] Waiting for credentials via HTTP...");
    bool got = (xSemaphoreTake(provSem, ticks) == pdTRUE);

    if (got) {
        Serial.println("[Provision] Credentials received!");
    } else {
        Serial.println("[Provision] Timeout waiting for credentials");
    }
    return got;
}

const char* wifi_provision::getApIp() {
    static char ipBuf[16];
    strncpy(ipBuf, WiFi.softAPIP().toString().c_str(), sizeof(ipBuf) - 1);
    return ipBuf;
}

const char* wifi_provision::getApName() {
    return apNameBuf;
}
