#include "device_server.h"
#include <WebServer.h>
#include <WiFi.h>
#include <ArduinoJson.h>
#include <Arduino.h>

static WebServer* server = nullptr;
static char versionBuf[16] = {};

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
