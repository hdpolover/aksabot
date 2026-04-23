#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClient.h>
#include <WiFiServer.h>
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

// Core 1: raw MJPEG TCP server on port 81 — one client at a time
void mjpegTask(void*) {
    WiFiServer svr(81);
    svr.begin();
    Serial.println("[BOOT] MJPEG server on port 81");
    while (true) {
        WiFiClient client = svr.accept();
        if (client) {
            Serial.println("[STREAM] client connected");
            // drain the HTTP request headers before sending response
            while (client.connected()) {
                if (client.available()) {
                    String line = client.readStringUntil('\n');
                    if (line == "\r") break;  // blank line = end of headers
                }
            }
            client.print(
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
                "Access-Control-Allow-Origin: *\r\n"
                "Cache-Control: no-cache\r\n"
                "\r\n");
            while (client.connected()) {
                camera_fb_t* fb = nullptr;
                if (xQueueReceive(frameQueue, &fb, pdMS_TO_TICKS(300)) != pdTRUE || !fb) continue;

                // copy to PSRAM and release camera buffer immediately — don't hold
                // the camera buffer during the slow TCP write (causes capture stall)
                uint8_t* buf = (uint8_t*)ps_malloc(fb->len);
                size_t   len = fb->len;
                if (buf) memcpy(buf, fb->buf, len);
                camera::returnFrame(fb);

                if (!buf) continue;  // PSRAM alloc failed, skip frame

                char hdr[80];
                int hlen = snprintf(hdr, sizeof(hdr),
                    "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %zu\r\n\r\n", len);
                client.write((const uint8_t*)hdr, hlen);
                client.write(buf, len);
                client.print("\r\n");
                free(buf);
            }
            client.stop();
            Serial.println("[STREAM] client disconnected");
        }
        vTaskDelay(pdMS_TO_TICKS(10));
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
    if (!frameQueue) {
        Serial.println("[ERROR] Queue create failed — halting");
        while (true) delay(1000);
    }

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.print("[BOOT] WiFi connecting");
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.printf("\n[BOOT] IP=%s\n", WiFi.localIP().toString().c_str());

    // All tasks on Core 1 — Core 0 left free for WiFi driver
    xTaskCreatePinnedToCore(captureLoop, "capture", 8192, nullptr, 5, nullptr, 1);
    xTaskCreatePinnedToCore(mjpegTask,   "mjpeg",   8192, nullptr, 4, nullptr, 1);
    xTaskCreatePinnedToCore(serverLoop,  "server",  8192, nullptr, 3, nullptr, 1);

    Serial.printf("[BOOT] Web UI:    http://%s/\n",       WiFi.localIP().toString().c_str());
    Serial.printf("[BOOT] Stream:    http://%s:81\n",     WiFi.localIP().toString().c_str());
    Serial.printf("[BOOT] Status:    http://%s/status\n", WiFi.localIP().toString().c_str());
}

void loop() {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[WIFI] Reconnecting...");
        WiFi.reconnect();
    }
    vTaskDelay(pdMS_TO_TICKS(5000));
}
