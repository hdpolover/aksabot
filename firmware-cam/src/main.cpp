#include <Arduino.h>
#include <WiFi.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include "camera.h"
#include "motion.h"
#include "metrics.h"
#include "stream_server.h"
#include "credentials.h"

QueueHandle_t frameQueue = nullptr;

// Core 0: capture frames, check motion, push to queue
void captureLoop(void*) {
    while (true) {
        camera_fb_t* fb = camera::capture();
        if (fb) {
            metrics::onFrame(fb->len);
            motion::checkSize(fb->len);

            // drop oldest frame if queue full so capture never blocks
            camera_fb_t* old = nullptr;
            if (xQueueReceive(frameQueue, &old, 0) == pdTRUE && old) {
                camera::returnFrame(old);
            }
            xQueueSend(frameQueue, &fb, 0);
        }
        vTaskDelay(1);
    }
}

// Core 1: HTTP server + metrics tick
void serverLoop(void*) {
    stream_server::start();
    while (true) {
        metrics::tick(motion::detected());
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("\n[BOOT] ESP32-CAM firmware starting");

    if (!camera::init()) {
        Serial.println("[ERROR] Camera init failed — halting");
        while (true) delay(1000);
    }
    Serial.println("[BOOT] OV3660 OK");

    motion::init(15);
    frameQueue = xQueueCreate(1, sizeof(camera_fb_t*));

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.print("[BOOT] WiFi connecting");
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.printf("\n[BOOT] IP=%s\n", WiFi.localIP().toString().c_str());

    xTaskCreatePinnedToCore(captureLoop, "capture", 8192, nullptr, 5, nullptr, 0);
    xTaskCreatePinnedToCore(serverLoop,  "server",  8192, nullptr, 3, nullptr, 1);

    Serial.printf("[BOOT] Web UI:    http://%s/\n",      WiFi.localIP().toString().c_str());
    Serial.printf("[BOOT] Stream:    http://%s/stream\n", WiFi.localIP().toString().c_str());
    Serial.printf("[BOOT] Status:    http://%s/status\n", WiFi.localIP().toString().c_str());
}

void loop() {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[WIFI] Reconnecting...");
        WiFi.reconnect();
    }
    vTaskDelay(pdMS_TO_TICKS(5000));
}
