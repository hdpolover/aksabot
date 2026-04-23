#include "stream_server.h"
#include "camera.h"
#include "metrics.h"
#include "motion.h"
#include "esp_http_server.h"
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

extern QueueHandle_t frameQueue;

static httpd_handle_t _server = nullptr;

// ---- Web UI (inline HTML) ----
static const char INDEX_HTML[] =
"<!DOCTYPE html><html><head><title>ESP32-CAM</title>"
"<style>body{font-family:monospace;background:#111;color:#0f0;margin:20px}"
"img{max-width:100%;border:1px solid #0f0;display:block;margin-bottom:10px}"
"select,button,input{background:#222;color:#0f0;border:1px solid #0f0;padding:4px 8px;margin:4px}"
".on{color:#f00}.off{color:#0f0}</style></head><body>"
"<h2>ESP32-CAM Test Harness</h2>"
"<img src='/stream'>"
"<div id='s'>Loading...</div>"
"<div>Res:<select id='r'>"
"<option value='0'>QQVGA 160x120</option>"
"<option value='4'>QVGA 320x240</option>"
"<option value='5' selected>VGA 640x480</option>"
"<option value='8'>SVGA 800x600</option>"
"<option value='13'>UXGA 1600x1200</option>"
"</select><button onclick=\"fetch('/config?res='+document.getElementById('r').value)\">Apply</button></div>"
"<div>Motion:<button onclick=\"fetch('/status').then(r=>r.json()).then(d=>fetch('/config?motion='+(d.motion_enabled?0:1)))\">Toggle</button>"
"Threshold:<input type='number' id='t' value='15' min='0' max='100' style='width:50px'>"
"<button onclick=\"fetch('/config?threshold='+document.getElementById('t').value)\">Set</button></div>"
"<script>setInterval(()=>{"
"fetch('/status').then(r=>r.json()).then(d=>{"
"document.getElementById('s').innerHTML="
"'FPS:'+d.fps+' | '+d.frame_ms+'ms | Heap:'+d.heap_kb+'KB | PSRAM:'+d.psram_kb+'KB | Motion:<span class=\"'+(d.motion?'on\">DETECTED':'off\">clear')+'</span>'"
";});},1000);</script></body></html>";

// ---- Handlers ----

static esp_err_t indexHandler(httpd_req_t* req) {
    httpd_resp_set_type(req, "text/html");
    httpd_resp_send(req, INDEX_HTML, (ssize_t)strlen(INDEX_HTML));
    return ESP_OK;
}

static esp_err_t streamHandler(httpd_req_t* req) {
    httpd_resp_set_type(req, "multipart/x-mixed-replace; boundary=--frame");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    httpd_resp_set_hdr(req, "Cache-Control", "no-cache");

    char hdr[80];
    while (true) {
        camera_fb_t* fb = nullptr;
        if (xQueueReceive(frameQueue, &fb, pdMS_TO_TICKS(300)) != pdTRUE || !fb) continue;

        size_t hlen = snprintf(hdr, sizeof(hdr),
            "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %zu\r\n\r\n", fb->len);

        esp_err_t res = httpd_resp_send_chunk(req, hdr, (ssize_t)hlen);
        if (res == ESP_OK) res = httpd_resp_send_chunk(req, (const char*)fb->buf, (ssize_t)fb->len);
        if (res == ESP_OK) res = httpd_resp_send_chunk(req, "\r\n", 2);
        camera::returnFrame(fb);

        if (res != ESP_OK) break;  // client disconnected
    }
    return ESP_OK;
}

static esp_err_t statusHandler(httpd_req_t* req) {
    char json[256];
    snprintf(json, sizeof(json),
        "{\"fps\":%d,\"frame_ms\":%d,\"heap_kb\":%u,\"psram_kb\":%u"
        ",\"motion\":%s,\"motion_enabled\":%s,\"motion_score\":%d}",
        metrics::fps(), metrics::frameMs(),
        ESP.getFreeHeap()  / 1024,
        ESP.getFreePsram() / 1024,
        motion::detected()  ? "true" : "false",
        motion::isEnabled() ? "true" : "false",
        motion::lastScore());
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    httpd_resp_send(req, json, (ssize_t)strlen(json));
    return ESP_OK;
}

static esp_err_t configHandler(httpd_req_t* req) {
    char query[128] = {};
    char val[16]    = {};
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
        if (httpd_query_key_value(query, "res",       val, sizeof(val)) == ESP_OK)
            camera::setResolution(atoi(val));
        if (httpd_query_key_value(query, "motion",    val, sizeof(val)) == ESP_OK)
            motion::setEnabled(atoi(val) != 0);
        if (httpd_query_key_value(query, "threshold", val, sizeof(val)) == ESP_OK)
            motion::setThreshold(atoi(val));
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-cache");
    httpd_resp_send(req, "{\"ok\":true}", 11);
    return ESP_OK;
}

// ---- Public ----

namespace stream_server {

bool start() {
    httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
    cfg.server_port     = 80;
    cfg.max_open_sockets = 5;
    cfg.stack_size       = 8192;

    if (httpd_start(&_server, &cfg) != ESP_OK) {
        Serial.println("[ERROR] HTTP server start failed");
        return false;
    }

    const httpd_uri_t uris[] = {
        { "/",       HTTP_GET, indexHandler,  nullptr },
        { "/stream", HTTP_GET, streamHandler, nullptr },
        { "/status", HTTP_GET, statusHandler, nullptr },
        { "/config", HTTP_GET, configHandler, nullptr },
    };
    for (const auto& u : uris) httpd_register_uri_handler(_server, &u);

    Serial.println("[BOOT] HTTP server started on port 80");
    return true;
}

} // namespace stream_server
