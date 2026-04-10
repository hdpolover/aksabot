#include <Arduino.h>
#include <ArduinoJson.h>
#include "config.h"
#include "state.h"
#include "nvs_store.h"
#include "wifi_manager.h"
#include "ws_client.h"
#include "audio_io.h"
#include "opus_codec.h"
#include "sd_storage.h"
#include "tts_cache.h"
#include "presence_detector.h"
#include "recording_buffer.h"
#include "resilience_audio.h"
#include "display.h"
#include "face.h"
#include "touch.h"
#include "vad.h"
#include "ota_update.h"
#include "debug_log.h"
#include "power_manager.h"

// Global application state
AppState appState;

// ── Audio buffers (PSRAM) ───────────────────────────────
static int16_t* pcmBuffer = nullptr;
static uint8_t* opusBuffer = nullptr;
static int16_t* playbackBuffer = nullptr;

// ── FreeRTOS task handles ───────────────────────────────
static TaskHandle_t audioCaptureTask = nullptr;
static TaskHandle_t wsTask = nullptr;
static TaskHandle_t displayTask = nullptr;

// ── TTS cache accumulation ─────────────────────────────
static uint8_t* cacheAccumBuf = nullptr;
static size_t cacheAccumLen = 0;
static const size_t CACHE_ACCUM_MAX = 256 * 1024;

// ── BotState → face expression mapping ─────────────────

static void syncFaceToState() {
    switch (appState.botState) {
        case BotState::IDLE:
            face::setExpression(face::Expression::IDLE);
            break;
        case BotState::LISTENING:
            face::setExpression(face::Expression::LISTENING, 100);
            break;
        case BotState::THINKING:
            face::setExpression(face::Expression::THINKING, 150);
            break;
        case BotState::SPEAKING:
            face::setExpression(face::Expression::SPEAKING, 100);
            break;
        case BotState::OFFLINE:
            face::setExpression(face::Expression::OFFLINE, 300);
            break;
        case BotState::SLEEPING:
            face::setExpression(face::Expression::SLEEPING, 500);
            break;
    }
}

static void updateStatusBar() {
    display::StatusBar sb = {};
    sb.wifiConnected = appState.wifiConnected;
    sb.wsConnected = appState.wsConnected;
    sb.wifiRssi = WiFi.RSSI();
    sb.batteryPercent = 255;  // USB-powered
    sb.focusModeActive = false;
    sb.pomodoroActive = false;
    display::updateStatusBar(sb);
}

// ── WebSocket event handlers ────────────────────────────

static void onWsJson(const char* event, const char* data) {
    if (strcmp(event, "state:update") == 0) {
        Serial.printf("[Main] State update: %s\n", data);
    }
    else if (strcmp(event, "session:start") == 0) {
        Serial.printf("[Main] Session started: %s\n", data);
        if (recording_buffer::hasPending()) {
            recording_buffer::resendPending();
        }
    }
    else if (strcmp(event, "session:end") == 0) {
        Serial.printf("[Main] Session ended: %s\n", data);
    }
    else if (strcmp(event, "transcript:partial") == 0) {
        Serial.printf("[Main] STT partial: %s\n", data);
        display::setTranscriptText("You", data);
    }
    else if (strcmp(event, "transcript:final") == 0) {
        Serial.printf("[Main] STT final: %s\n", data);
        display::setTranscriptText("You", data);
    }
    else if (strcmp(event, "response:start") == 0) {
        appState.botState = BotState::SPEAKING;
        syncFaceToState();
        cacheAccumLen = 0;
        Serial.println("[Main] Response start — playing audio");
    }
    else if (strcmp(event, "response:text") == 0) {
        Serial.printf("[Main] LLM: %s\n", data);
        display::setTranscriptText("Aksa", data);
    }
    else if (strcmp(event, "response:end") == 0) {
        if (data && data[0] != '\0') {
            JsonDocument endDoc;
            if (deserializeJson(endDoc, data) == DeserializationError::Ok) {
                const char* key = endDoc["cacheKey"] | (const char*)nullptr;
                if (key && strlen(key) > 0 && cacheAccumBuf && cacheAccumLen > 0) {
                    tts_cache::save(key, cacheAccumBuf, cacheAccumLen);
                }
            }
        }
        cacheAccumLen = 0;
        appState.botState = BotState::IDLE;
        syncFaceToState();
        Serial.println("[Main] Response end");
    }
    else if (strcmp(event, "error") == 0) {
        Serial.printf("[Main] Error: %s\n", data);
        face::setExpression(face::Expression::CONFUSED, 200);
        appState.botState = BotState::IDLE;
    }
    // ── Proactive events → display mode switching ────────
    else if (strcmp(event, "proactive:reminder") == 0) {
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            display::ReminderData rd = {};
            const char* text = doc["text"] | "Reminder";
            strncpy(rd.text, text, sizeof(rd.text) - 1);
            rd.durationMs = doc["durationMs"] | 5000;
            const char* type = doc["type"] | "";
            strncpy(rd.icon, type, sizeof(rd.icon) - 1);

            // Set face expression based on reminder type
            if (strcmp(type, "eyeBreak") == 0) {
                face::setExpression(face::Expression::CALM, 200);
            } else {
                face::setExpression(face::Expression::ENCOURAGING, 200);
            }

            display::showReminder(rd);
        }
    }
    else if (strcmp(event, "proactive:pomodoro") == 0) {
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            const char* action = doc["action"] | "";

            if (strcmp(action, "stop") == 0) {
                display::setMode(display::Mode::FACE);
                face::setExpression(face::Expression::IDLE);
            } else {
                display::PomodoroData pd = {};
                const char* phase = doc["phase"] | "focus";
                strncpy(pd.phaseLabel, phase, sizeof(pd.phaseLabel) - 1);
                pd.currentCycle = doc["cycle"] | 1;
                pd.totalCycles = 4;
                pd.remainingSeconds = (doc["durationMinutes"] | 25) * 60;

                if (strcmp(phase, "focus") == 0 || strcmp(phase, "work") == 0) {
                    face::setExpression(face::Expression::FOCUSED, 200);
                } else {
                    face::setExpression(face::Expression::CALM, 200);
                }

                display::showPomodoro(pd);
            }
        }
    }
    else if (strcmp(event, "ota:start") == 0) {
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            const char* url = doc["url"] | "";
            const char* sha256 = doc["sha256"] | "";
            const char* version = doc["version"] | "unknown";
            if (strlen(url) > 0 && strlen(sha256) > 0) {
                ota_update::start(url, sha256, version);
            }
        }
    }
    else {
        Serial.printf("[Main] Unknown event: %s = %s\n", event, data);
    }
}

static void onWsBinary(const uint8_t* data, size_t len) {
    int samples = opus_codec::decode(data, len, playbackBuffer, OPUS_FRAME_SAMPLES);
    if (samples > 0) {
        audio_io::writeSpeaker(playbackBuffer, samples);

        // Feed audio amplitude to face for mouth animation
        int32_t sum = 0;
        for (int i = 0; i < samples; i++) {
            sum += abs(playbackBuffer[i]);
        }
        float amplitude = (float)sum / (samples * 32768.0f);
        face::feedAudioAmplitude(amplitude);
    }

    if (cacheAccumBuf && (cacheAccumLen + len) <= CACHE_ACCUM_MAX) {
        memcpy(cacheAccumBuf + cacheAccumLen, data, len);
        cacheAccumLen += len;
    }
}

// ── Touch event handler ────────────────────────────────

static void onTouchEvent(touch::Event event) {
    // Any touch interaction resets idle timer
    power_manager::recordInteraction();

    switch (event) {
        case touch::Event::HOLD_START:
            // Start recording
            if (appState.botState == BotState::IDLE && appState.wsConnected) {
                appState.botState = BotState::LISTENING;
                syncFaceToState();
                ws_client::sendEvent("audio:start");
                Serial.println("[Main] Recording started");
            }
            break;

        case touch::Event::HOLD_END:
            // Stop recording
            if (appState.botState == BotState::LISTENING) {
                appState.botState = BotState::THINKING;
                syncFaceToState();
                ws_client::sendEvent("audio:end");
                audio_io::stopMic();
                Serial.println("[Main] Recording stopped, waiting for response...");
            }
            break;

        case touch::Event::TAP:
            // Interrupt playback, or dismiss reminder
            if (appState.botState == BotState::SPEAKING) {
                appState.interrupted = true;
                appState.botState = BotState::IDLE;
                syncFaceToState();
                ws_client::sendEvent("audio:interrupt");
                audio_io::stopSpeaker();
                Serial.println("[Main] Interrupted");
            }
            else if (display::getMode() == display::Mode::REMINDER) {
                display::setMode(display::Mode::FACE);
                ws_client::sendEvent("proactive:dismiss");
            }
            break;

        case touch::Event::LONG_PRESS:
            // End session
            ws_client::sendEvent("session:end");
            appState.botState = BotState::IDLE;
            syncFaceToState();
            Serial.println("[Main] Session ended");
            break;

        case touch::Event::WAKE:
            // Display handles wake — just log
            Serial.println("[Main] Woke from touch");
            break;
    }
}

// ── Audio capture task (Core 0, high priority) ──────────

static bool audioInitialized = false;

static void audioCaptureLoop(void* param) {
    for (;;) {
        // Skip if audio I/O not initialized (ES8311 codec not set up yet)
        if (!audioInitialized) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }
        if (appState.botState != BotState::LISTENING) {
            if (recording_buffer::isBuffering()) {
                recording_buffer::stopBuffering();
            }
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        size_t samplesRead = audio_io::readMic(pcmBuffer, OPUS_FRAME_SAMPLES);
        if (samplesRead == 0) continue;

        // VAD: check for end-of-speech (auto-stop recording)
        vad::Result vadResult = vad::analyze(pcmBuffer, samplesRead);
        if (vadResult == vad::Result::END_OF_SPEECH) {
            appState.botState = BotState::THINKING;
            syncFaceToState();
            ws_client::sendEvent("audio:end");
            audio_io::stopMic();
            vad::reset();
            Serial.println("[Main] VAD: end-of-speech detected, stopping recording");
            continue;
        }

        int opusBytes = opus_codec::encode(pcmBuffer, opusBuffer, OPUS_MAX_FRAME_BYTES);
        if (opusBytes > 0) {
            if (appState.wsConnected) {
                if (recording_buffer::isBuffering()) {
                    recording_buffer::stopBuffering();
                }
                ws_client::sendBinary(opusBuffer, opusBytes);
                vTaskDelay(pdMS_TO_TICKS(5));  // Yield to let WS poll task breathe
            } else {
                if (!recording_buffer::isBuffering()) {
                    recording_buffer::startBuffering();
                }
                recording_buffer::writeFrame(opusBuffer, opusBytes);
            }
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

// ── Display task (Core 1) ──────────────────────────────

static void displayLoop(void* param) {
    for (;;) {
        display::tick(millis());
        vTaskDelay(pdMS_TO_TICKS(33));  // ~30fps
    }
}

// ── Setup & Loop ────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n=== Aksabot Firmware ===\n");

    // Allocate audio buffers in PSRAM
    // pcmBuffer is 2x because readMic reads stereo then extracts mono in-place
    pcmBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * 2 * sizeof(int16_t));
    opusBuffer = (uint8_t*)ps_malloc(OPUS_MAX_FRAME_BYTES);
    playbackBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * sizeof(int16_t));
    cacheAccumBuf = (uint8_t*)ps_malloc(CACHE_ACCUM_MAX);

    if (!pcmBuffer || !opusBuffer || !playbackBuffer) {
        Serial.println("[Main] FATAL: Failed to allocate PSRAM buffers");
        while (true) { delay(1000); }
    }
    Serial.printf("[Main] PSRAM free: %u bytes\n", ESP.getFreePsram());

    // 1. Debug logging (first so all modules can use LOG macros)
    debug_log::init();

    // 2. NVS
    nvs_store::init();

    // 2. MicroSD (SDIO 4-bit)
    sd_storage::init();

    // 3. TTS cache + recording buffer + resilience audio (depend on SD)
    tts_cache::init();
    recording_buffer::init();
    resilience_audio::init();

    // 4. Presence detector
    {
        presence_detector::Config presCfg;
        presCfg.rssiThreshold = nvs_store::getPresenceRssiThreshold();
        presCfg.gracePeriodSec = nvs_store::getPresenceGracePeriodSec();
        presence_detector::init(presCfg);

        presence_detector::onStateChange([](PresenceState newState, PresenceState oldState, uint32_t awaySec) {
            if (newState == PresenceState::PRESENT && oldState == PresenceState::AWAY && appState.wsConnected) {
                char payload[48];
                snprintf(payload, sizeof(payload), "{\"awayDurationSeconds\":%u}", awaySec);
                ws_client::sendEvent("presence:arrived", payload);
                display::wake();
            }
            else if (newState == PresenceState::AWAY) {
                if (appState.wsConnected) {
                    ws_client::sendEvent("presence:departed");
                }
                display::sleep();
            }
        });
    }

    // 5. Display + face + touch
    display::init();
    touch::init();
    touch::onEvent(onTouchEvent);

    // 5b. Voice Activity Detection
    vad::init();

    // 5c. OTA subsystem
    ota_update::init();

    // 5d. Power management
    power_manager::init();

    // 6. Opus codec
    if (!opus_codec::init()) {
        Serial.println("[Main] FATAL: Opus init failed");
        while (true) { delay(1000); }
    }

    // 7. Audio I/O (ES8311 codec + I2S)
    audio_io::init();
    audioInitialized = true;

    // 8. Wi-Fi
    wifi_manager::init();
    Serial.println("[Main] Waiting for Wi-Fi...");
    wifi_manager::waitForConnection(15000);

    if (!wifi_manager::isConnected()) {
        Serial.println("[Main] Wi-Fi failed — continuing in offline mode");
        appState.botState = BotState::OFFLINE;
        syncFaceToState();
    }

    // 9. WebSocket
    ws_client::init(onWsJson, onWsBinary);
    if (wifi_manager::isConnected()) {
        ws_client::connect();
    }

    // 10. Start FreeRTOS tasks
    xTaskCreatePinnedToCore(audioCaptureLoop, "audio_cap", 8192, nullptr, 5, &audioCaptureTask, 0);
    xTaskCreatePinnedToCore(wsLoop, "ws_poll", 8192, nullptr, 3, &wsTask, 1);
    xTaskCreatePinnedToCore(displayLoop, "display", 8192, nullptr, 3, &displayTask, 1);

    // Wait for WS connection
    unsigned long wsStart = millis();
    while (!appState.wsConnected && (millis() - wsStart) < 5000) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    if (appState.wsConnected) {
        appState.botState = BotState::IDLE;
        syncFaceToState();
        Serial.println("\n[Main] Ready! Controls: s=start, e=end, i=interrupt, q=quit, w=wake\n");
    } else {
        Serial.println("\n[Main] WebSocket not connected — will auto-reconnect\n");
    }

    updateStatusBar();
}

void loop() {
    uint32_t now = millis();

    // Process touch (serial simulation or hardware)
    touch::processSerial(now);
    touch::tick(now);

    // Tick presence detector
    presence_detector::tick(now);

    // Tick power management
    power_manager::tick(now);

    // Sync connectivity state
    BotState prevState = appState.botState;
    if (!appState.wifiConnected && appState.botState != BotState::OFFLINE) {
        appState.botState = BotState::OFFLINE;
    } else if (appState.wsConnected && appState.botState == BotState::OFFLINE) {
        appState.botState = BotState::IDLE;
    }

    if (appState.botState != prevState) {
        syncFaceToState();
        updateStatusBar();
    }

    vTaskDelay(pdMS_TO_TICKS(10));
}
