#include <Arduino.h>
#include "config.h"
#include "state.h"
#include "wifi_manager.h"
#include "ws_client.h"
#include "audio_io.h"
#include "opus_codec.h"
#include "sd_storage.h"

// Global application state
AppState appState;

// ── Audio buffers (PSRAM) ───────────────────────────────
static int16_t* pcmBuffer = nullptr;
static uint8_t* opusBuffer = nullptr;
static int16_t* playbackBuffer = nullptr;

// ── FreeRTOS task handles ───────────────────────────────
static TaskHandle_t audioCaptureTask = nullptr;
static TaskHandle_t wsTask = nullptr;

// ── WebSocket event handlers ────────────────────────────

static void onWsJson(const char* event, const char* data) {
    if (strcmp(event, "state:update") == 0) {
        Serial.printf("[Main] State update: %s\n", data);
    }
    else if (strcmp(event, "session:start") == 0) {
        Serial.printf("[Main] Session started: %s\n", data);
    }
    else if (strcmp(event, "session:end") == 0) {
        Serial.printf("[Main] Session ended: %s\n", data);
    }
    else if (strcmp(event, "transcript:partial") == 0) {
        Serial.printf("[Main] STT partial: %s\n", data);
    }
    else if (strcmp(event, "transcript:final") == 0) {
        Serial.printf("[Main] STT final: %s\n", data);
    }
    else if (strcmp(event, "response:start") == 0) {
        appState.botState = BotState::SPEAKING;
        Serial.println("[Main] Response start — playing audio");
    }
    else if (strcmp(event, "response:text") == 0) {
        Serial.printf("[Main] LLM: %s\n", data);
    }
    else if (strcmp(event, "response:end") == 0) {
        appState.botState = BotState::IDLE;
        Serial.println("[Main] Response end");
    }
    else if (strcmp(event, "error") == 0) {
        Serial.printf("[Main] Error: %s\n", data);
        appState.botState = BotState::IDLE;
    }
    else {
        Serial.printf("[Main] Unknown event: %s = %s\n", event, data);
    }
}

static void onWsBinary(const uint8_t* data, size_t len) {
    // Decode Opus and play through speaker
    int samples = opus_codec::decode(data, len, playbackBuffer, OPUS_FRAME_SAMPLES);
    if (samples > 0) {
        audio_io::writeSpeaker(playbackBuffer, samples);
    }
}

// ── Audio capture task (Core 0, high priority) ──────────
// Reads mic → encodes Opus → sends over WebSocket

static void audioCaptureLoop(void* param) {
    for (;;) {
        // Only capture when in LISTENING state
        if (appState.botState != BotState::LISTENING) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        // Read one Opus frame of PCM from mic
        size_t samplesRead = audio_io::readMic(pcmBuffer, OPUS_FRAME_SAMPLES);
        if (samplesRead == 0) continue;

        // Encode to Opus
        int opusBytes = opus_codec::encode(pcmBuffer, opusBuffer, OPUS_MAX_FRAME_BYTES);
        if (opusBytes > 0) {
            ws_client::sendBinary(opusBuffer, opusBytes);
        }
    }
}

// ── WebSocket polling task (Core 1) ─────────────────────

static void wsLoop(void* param) {
    for (;;) {
        ws_client::poll();
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

// ── Touch handling (placeholder for Phase 2 touch driver) ──
// For Phase 1, we use a simple button or serial command to simulate touch.

static void handleTouch() {
    // Phase 1: Use Serial input to simulate touch-to-talk
    // Send 's' to start recording, 'e' to stop, 'i' to interrupt
    if (Serial.available()) {
        char c = Serial.read();
        switch (c) {
            case 's':  // Start recording
                if (appState.botState == BotState::IDLE && appState.wsConnected) {
                    appState.botState = BotState::LISTENING;
                    ws_client::sendEvent("audio:start");
                    Serial.println("[Main] Recording started (press 'e' to stop)");
                }
                break;

            case 'e':  // End recording
                if (appState.botState == BotState::LISTENING) {
                    appState.botState = BotState::THINKING;
                    ws_client::sendEvent("audio:end");
                    audio_io::stopMic();
                    Serial.println("[Main] Recording stopped, waiting for response...");
                }
                break;

            case 'i':  // Interrupt
                if (appState.botState == BotState::SPEAKING) {
                    appState.interrupted = true;
                    appState.botState = BotState::IDLE;
                    ws_client::sendEvent("audio:interrupt");
                    audio_io::stopSpeaker();
                    Serial.println("[Main] Interrupted");
                }
                break;

            case 'q':  // End session
                ws_client::sendEvent("session:end");
                appState.botState = BotState::IDLE;
                Serial.println("[Main] Session ended");
                break;
        }
    }
}

// ── Setup & Loop ────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n=== Aksabot Firmware ===\n");

    // Allocate audio buffers in PSRAM
    pcmBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * sizeof(int16_t));
    opusBuffer = (uint8_t*)ps_malloc(OPUS_MAX_FRAME_BYTES);
    playbackBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * sizeof(int16_t));

    if (!pcmBuffer || !opusBuffer || !playbackBuffer) {
        Serial.println("[Main] FATAL: Failed to allocate PSRAM buffers");
        while (true) { delay(1000); }
    }
    Serial.printf("[Main] PSRAM free: %u bytes\n", ESP.getFreePsram());

    // 1. MicroSD (non-blocking, ok to fail)
    sd_storage::init();

    // 2. Opus codec
    if (!opus_codec::init()) {
        Serial.println("[Main] FATAL: Opus init failed");
        while (true) { delay(1000); }
    }

    // 3. Audio I/O
    audio_io::init();

    // 4. Wi-Fi
    wifi_manager::init();
    Serial.println("[Main] Waiting for Wi-Fi...");
    wifi_manager::waitForConnection(15000);

    if (!wifi_manager::isConnected()) {
        Serial.println("[Main] Wi-Fi failed — continuing in offline mode");
        appState.botState = BotState::OFFLINE;
    }

    // 5. WebSocket
    ws_client::init(onWsJson, onWsBinary);
    if (wifi_manager::isConnected()) {
        ws_client::connect();
    }

    // 6. Start FreeRTOS tasks
    xTaskCreatePinnedToCore(audioCaptureLoop, "audio_cap", 4096, nullptr, 5, &audioCaptureTask, 0);
    xTaskCreatePinnedToCore(wsLoop, "ws_poll", 8192, nullptr, 3, &wsTask, 1);

    // Wait for WS connection
    unsigned long wsStart = millis();
    while (!appState.wsConnected && (millis() - wsStart) < 5000) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    if (appState.wsConnected) {
        appState.botState = BotState::IDLE;
        Serial.println("\n[Main] Ready! Controls: s=start, e=end, i=interrupt, q=quit session\n");
    } else {
        Serial.println("\n[Main] WebSocket not connected — will auto-reconnect\n");
    }
}

void loop() {
    // Handle serial-based touch simulation
    handleTouch();

    // Update state based on connectivity
    if (!appState.wifiConnected && appState.botState != BotState::OFFLINE) {
        appState.botState = BotState::OFFLINE;
    } else if (appState.wsConnected && appState.botState == BotState::OFFLINE) {
        appState.botState = BotState::IDLE;
    }

    vTaskDelay(pdMS_TO_TICKS(10));
}
