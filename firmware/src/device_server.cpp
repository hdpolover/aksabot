#include "device_server.h"
#include "nvs_store.h"
#include <WebServer.h>
#include <WiFi.h>
#include <ArduinoJson.h>
#include <Arduino.h>

static WebServer* server = nullptr;
static char versionBuf[16] = {};
static volatile bool tokenJustReceived = false;

void device_server::start(const char* version) {
    strncpy(versionBuf, version, sizeof(versionBuf) - 1);
    versionBuf[sizeof(versionBuf) - 1] = '\0';

    server = new WebServer(80);

    // GET / — lightweight ping / identification
    server->on("/", HTTP_GET, []() {
        server->sendHeader("Access-Control-Allow-Origin", "*");
        server->send(200, "text/plain", "Aksabot");
    });

    // GET /status — JSON device identity used by the Flutter app during mDNS discovery
    server->on("/status", HTTP_GET, []() {
        JsonDocument doc;
        doc["name"]    = "Aksabot";
        doc["version"] = versionBuf;
        doc["mac"]     = WiFi.macAddress();
        doc["ip"]      = WiFi.localIP().toString();

        String out;
        serializeJson(doc, out);
        server->sendHeader("Access-Control-Allow-Origin", "*");
        server->send(200, "application/json", out);
    });

    // POST /token — receives device token from Flutter app after backend registration
    server->on("/token", HTTP_POST, []() {
        const String body = server->arg("plain");
        JsonDocument doc;
        if (deserializeJson(doc, body) != DeserializationError::Ok) {
            server->send(400, "application/json", "{\"error\":\"invalid JSON\"}");
            return;
        }

        const char* token = doc["token"] | (const char*)nullptr;
        if (!token || strlen(token) == 0) {
            server->send(400, "application/json", "{\"error\":\"token required\"}");
            return;
        }

        nvs_store::setDeviceToken(token);

        // Optional: backend URL override
        const char* backendUrl = doc["backendUrl"] | (const char*)nullptr;
        if (backendUrl && strlen(backendUrl) > 0) {
            nvs_store::setBackendUrl(backendUrl);
        }

        server->sendHeader("Access-Control-Allow-Origin", "*");
        server->send(200, "application/json", "{\"ok\":true}");
        Serial.println("[DeviceServer] Device token saved via HTTP — will reconnect WS");
        tokenJustReceived = true;
    });

    server->onNotFound([]() {
        server->send(404, "text/plain", "not found");
    });

    server->begin();
    Serial.println("[DeviceServer] HTTP server started on port 80");
}

void device_server::tick() {
    if (server) {
        server->handleClient();
    }
}

void device_server::stop() {
    if (!server) return;
    server->stop();
    delete server;
    server = nullptr;
    Serial.println("[DeviceServer] Stopped");
}

bool device_server::consumeNewToken() {
    if (tokenJustReceived) {
        tokenJustReceived = false;
        return true;
    }
    return false;
}
