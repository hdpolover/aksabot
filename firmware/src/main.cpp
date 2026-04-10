#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <ESPmDNS.h>
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
#include "ble_manager.h"
#include "boot_screen.h"
#include "device_server.h"

#define FIRMWARE_VERSION "1.0.0"

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
        appState.botState = BotState::IDLE;
        syncFaceToState();
    }
    else if (strcmp(event, "state:update") == 0) {
        // Backend state sync (e.g., after STT error resets to idle)
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            const char* state = doc["state"] | "";
            if (strcmp(state, "idle") == 0 && appState.botState != BotState::IDLE) {
                Serial.println("[Main] Backend reset to idle");
                appState.botState = BotState::IDLE;
                syncFaceToState();
            }
        }
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

// Timer for reverting face expression after a visual feedback
static uint32_t faceRevertAtMs = 0;
static bool faceRevertPending = false;

static void scheduleFaceRevert(uint16_t delayMs) {
    faceRevertAtMs = millis() + delayMs;
    faceRevertPending = true;
}

static void onTouchEvent(touch::Event event) {
    // Any touch interaction resets idle timer
    power_manager::recordInteraction();

    switch (event) {
        case touch::Event::HOLD_START:
            if (appState.botState == BotState::IDLE) {
                if (appState.wsConnected) {
                    // Connected — start recording
                    appState.botState = BotState::LISTENING;
                    syncFaceToState();
                    ws_client::sendEvent("audio:start");
                    Serial.println("[Main] Recording started");
                } else {
                    // Not connected — show listening face briefly, then confused
                    face::setExpression(face::Expression::LISTENING, 100);
                    Serial.println("[Main] Hold detected but offline");
                }
            }
            break;

        case touch::Event::HOLD_END:
            if (appState.botState == BotState::LISTENING) {
                // Was recording — send to backend
                appState.botState = BotState::THINKING;
                syncFaceToState();
                ws_client::sendEvent("audio:end");
                audio_io::stopMic();
                Serial.println("[Main] Recording stopped, waiting for response...");
            } else if (!appState.wsConnected) {
                // Wasn't actually recording — show offline feedback
                face::setExpression(face::Expression::CONFUSED, 200);
                scheduleFaceRevert(1500);
                Serial.println("[Main] Not connected — can't send audio");
            }
            break;

        case touch::Event::TAP:
            if (appState.botState == BotState::SPEAKING) {
                // Interrupt playback
                appState.interrupted = true;
                appState.botState = BotState::IDLE;
                syncFaceToState();
                ws_client::sendEvent("audio:interrupt");
                audio_io::stopSpeaker();
                Serial.println("[Main] Interrupted");
            }
            else if (display::getMode() == display::Mode::REMINDER) {
                // Dismiss reminder
                display::setMode(display::Mode::FACE);
                ws_client::sendEvent("proactive:dismiss");
            }
            else if (appState.botState == BotState::IDLE) {
                // Idle tap — acknowledge with a brief expression change
                face::setExpression(face::Expression::ENCOURAGING, 150);
                scheduleFaceRevert(800);
            }
            break;

        case touch::Event::LONG_PRESS:
            // Only end session if not actively recording/processing
            if (appState.botState == BotState::LISTENING ||
                appState.botState == BotState::THINKING) {
                // Ignore long press during active voice interaction
                Serial.println("[Main] Long press ignored — recording active");
            } else {
                if (appState.wsConnected) {
                    ws_client::sendEvent("session:end");
                }
                appState.botState = BotState::IDLE;
                face::setExpression(face::Expression::CALM, 200);
                scheduleFaceRevert(1200);
                Serial.println("[Main] Session ended");
            }
            break;

        case touch::Event::WAKE:
            // Show a friendly wake expression
            face::setExpression(face::Expression::ENCOURAGING, 200);
            scheduleFaceRevert(1500);
            Serial.println("[Main] Woke from touch");
            break;
    }
}

// ── Audio capture task (Core 0, high priority) ──────────

static bool audioInitialized = false;

static void audioCaptureLoop(void* param) {
    bool stackLogged = false;
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
            stackLogged = false;
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        // One-time sync: wait for poll task to see LISTENING and exit.
        // client.poll() is non-blocking so this completes in <10ms.
        if (!stackLogged) {
            vTaskDelay(pdMS_TO_TICKS(60));
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

        // Log stack watermark once per recording session
        if (!stackLogged) {
            UBaseType_t hwm = uxTaskGetStackHighWaterMark(NULL);
            Serial.printf("[Audio] Stack watermark: %u bytes free\n", hwm * 4);
            stackLogged = true;
        }

        if (opusBytes > 0) {
            if (appState.wsConnected) {
                if (recording_buffer::isBuffering()) {
                    recording_buffer::stopBuffering();
                }
                ws_client::sendBinary(opusBuffer, opusBytes);
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
    Serial.println("[WS Task] Started on core " + String(xPortGetCoreID()));
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

    // ── 1. Core init (logging, NVS, PSRAM) ─────────────────
    debug_log::init();
    nvs_store::init();

    pcmBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * 2 * sizeof(int16_t));
    opusBuffer = (uint8_t*)ps_malloc(OPUS_MAX_FRAME_BYTES);
    playbackBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * sizeof(int16_t));
    cacheAccumBuf = (uint8_t*)ps_malloc(CACHE_ACCUM_MAX);
    if (!pcmBuffer || !opusBuffer || !playbackBuffer) {
        Serial.println("[Main] FATAL: Failed to allocate PSRAM buffers");
        while (true) { delay(1000); }
    }
    Serial.printf("[Main] PSRAM free: %u bytes\n", ESP.getFreePsram());

    // ── 2. Display init (early — needed for boot screen) ───
    display::init();

    // ── 3. Boot splash ─────────────────────────────────────
    boot_screen::init();
    boot_screen::showSplash(FIRMWARE_VERSION);

    // ── 4. Hardware checks ─────────────────────────────────
    boot_screen::showHardwareCheck("Display", 1);   // already working

    sd_storage::init();
    boot_screen::showHardwareCheck("MicroSD",
        sd_storage::isMounted() ? 1 : 3);  // 3=skipped if no card

    tts_cache::init();
    recording_buffer::init();
    resilience_audio::init();

    // Presence detector
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

    // Touch
    touch::init();
    touch::onEvent(onTouchEvent);
    boot_screen::showHardwareCheck("Touch", 1);

    // Audio
    audio_io::init();
    audioInitialized = true;
    boot_screen::showHardwareCheck("Audio (ES8311)", 1);

    // Opus codec
    bool opusOk = opus_codec::init();
    boot_screen::showHardwareCheck("Opus Codec", opusOk ? 1 : 2);
    if (!opusOk) {
        Serial.println("[Main] FATAL: Opus init failed");
        while (true) { delay(1000); }
    }

    // VAD, OTA, power
    vad::init();
    ota_update::init();
    power_manager::init();

    // BLE
    ble_manager::init();
    boot_screen::showHardwareCheck("Bluetooth LE", 1);

    delay(2000);  // Let user see the hardware check results

    // ── 5. First-boot detection ────────────────────────────
    bool firstBoot = nvs_store::isFirstBoot();
    if (firstBoot) {
        Serial.println("[Main] First boot detected — showing introduction");
        boot_screen::showFirstBoot();
    }

    // ── 6. BLE provisioning gate ───────────────────────────
    // Skip if NVS has credentials OR compile-time credentials exist.
    // wifi_manager::init() falls back to credentials.h when NVS is empty.
    bool hasNvsCreds = nvs_store::hasWifiCredentials();
    bool hasCompileCreds = (strlen(WIFI_SSID) > 0);

    if (!hasNvsCreds && !hasCompileCreds) {
        Serial.println("[Main] No WiFi credentials — entering provisioning mode");

        // Build SoftAP name from last 2 MAC bytes for uniqueness
        char apName[24];
        uint8_t mac[6];
        WiFi.macAddress(mac);
        snprintf(apName, sizeof(apName), "Aksabot-%02X%02X", mac[4], mac[5]);

        wifi_manager::startAP(apName);
        boot_screen::showProvisioningPrompt(apName);

        // Poll for either BLE or SoftAP HTTP to deliver credentials
        bool bleConnectedShown = false;
        while (!ble_manager::isProvisioned() && !wifi_manager::isAPProvisioned()) {
            uint32_t now = millis();
            if (!bleConnectedShown && ble_manager::isClientConnected()) {
                boot_screen::showProvisioningStatus("Phone connected via BLE...");
                bleConnectedShown = true;
            }
            boot_screen::tickProvisioningAnimation(now);
            wifi_manager::tickAP();
            delay(100);
        }

        wifi_manager::stopAP();

        const char* method = ble_manager::isProvisioned() ? "BLE" : "Wi-Fi hotspot";
        char statusMsg[48];
        snprintf(statusMsg, sizeof(statusMsg), "Credentials received via %s", method);
        boot_screen::showProvisioningStatus(statusMsg);
        Serial.printf("[Main] Provisioned via %s\n", method);
        delay(600);
    } else if (hasNvsCreds) {
        Serial.println("[Main] Using NVS WiFi credentials");
    } else {
        Serial.println("[Main] Using compile-time WiFi credentials");
    }

    // ── 7. WiFi connect ────────────────────────────────────
    char ssidBuf[64] = {};
    const char* ssidDisplay = WIFI_SSID;
    if (nvs_store::getWifiSsid(ssidBuf, sizeof(ssidBuf)) && strlen(ssidBuf) > 0) {
        ssidDisplay = ssidBuf;
    }
    boot_screen::showConnecting(ssidDisplay);

    wifi_manager::init();
    Serial.println("[Main] Waiting for Wi-Fi...");
    wifi_manager::waitForConnection(15000);

    if (wifi_manager::isConnected()) {
        ble_manager::notifyWifiStatus(2);  // connected

        // mDNS: advertise as aksabot.local + _aksabot._tcp service on port 80
        if (MDNS.begin("aksabot")) {
            MDNS.addService("aksabot", "tcp", 80);
            Serial.println("[Main] mDNS: aksabot.local registered");
        } else {
            Serial.println("[Main] mDNS: failed to start");
        }

        // HTTP status server so the app can verify it found the right device
        device_server::start(FIRMWARE_VERSION);

        if (firstBoot) {
            // First successful WiFi connection — celebrate and mark done
            nvs_store::markSetupComplete();
            boot_screen::showSetupComplete(ssidDisplay);
        } else {
            boot_screen::showConnected(WiFi.localIP().toString().c_str());
        }
        appState.wifiConnected = true;
    } else {
        boot_screen::showConnectionFailed("Timeout — will retry in background");
        ble_manager::notifyWifiStatus(3);  // failed
        appState.botState = BotState::OFFLINE;
    }

    // ── 8. Initialize WS client (connects in background via ws task) ──
    ws_client::init(onWsJson, onWsBinary);
    if (wifi_manager::isConnected() && nvs_store::hasDeviceToken()) {
        Serial.println("[Main] Device token found — connecting to backend");
        ws_client::connect();
    } else if (!nvs_store::hasDeviceToken()) {
        Serial.println("[Main] No device token — register via Aksabot app to enable AI features");
    }

    // ── 9. Start FreeRTOS tasks ────────────────────────────
    xTaskCreatePinnedToCore(audioCaptureLoop, "audio_cap", 24576, nullptr, 5, &audioCaptureTask, 0);
    xTaskCreatePinnedToCore(wsLoop, "ws_poll", 12288, nullptr, 3, &wsTask, 1);
    xTaskCreatePinnedToCore(displayLoop, "display", 8192, nullptr, 3, &displayTask, 1);

    // ── 10. Start presence scanning ───────────────────────
    if (nvs_store::getPresenceEnabled()) {
        ble_manager::startPresenceScan();
    }

    // ── 11. Ready — transition to face UI ─────────────────
    if (appState.wifiConnected) {
        appState.botState = BotState::IDLE;
    }
    boot_screen::showReady();

    // Face UI takes over from here (via displayLoop task)
    syncFaceToState();
    updateStatusBar();
    Serial.println("\n[Main] Ready! Hold screen to talk.\n");
}

void loop() {
    uint32_t now = millis();

    // Process touch (serial simulation or hardware)
    touch::processSerial(now);
    touch::tick(now);

    // Revert face expression after visual feedback timeout
    if (faceRevertPending && now >= faceRevertAtMs) {
        faceRevertPending = false;
        syncFaceToState();
    }

    // Safety: auto-revert from THINKING/LISTENING if stuck for 15s
    static uint32_t stuckCheckMs = 0;
    if (appState.botState == BotState::THINKING || appState.botState == BotState::LISTENING) {
        if (stuckCheckMs == 0) {
            stuckCheckMs = now;
        } else if ((now - stuckCheckMs) > 15000) {
            Serial.println("[Main] Stuck state timeout — reverting to IDLE");
            appState.botState = BotState::IDLE;
            syncFaceToState();
            stuckCheckMs = 0;
        }
    } else {
        stuckCheckMs = 0;
    }

    // Serve HTTP status requests + token delivery (used by Flutter app)
    device_server::tick();

    // Check if device token was received via HTTP → connect to backend
    if (device_server::consumeNewToken() && wifi_manager::isConnected()) {
        Serial.println("[Main] New device token received — connecting to backend WS");
        ws_client::reconnectWithToken();
        ble_manager::notifyAuthStatus(1);  // 1 = token stored
        updateStatusBar();
    }

    // Tick presence detector + BLE scanner
    presence_detector::tick(now);
    ble_manager::tickPresenceScan(now);

    // Tick power management
    power_manager::tick(now);

    // Sync connectivity state
    BotState prevState = appState.botState;
    if (!appState.wifiConnected && appState.botState != BotState::OFFLINE) {
        appState.botState = BotState::OFFLINE;
    } else if (appState.wifiConnected && appState.botState == BotState::OFFLINE) {
        appState.botState = BotState::IDLE;
    }

    if (appState.botState != prevState) {
        syncFaceToState();
        updateStatusBar();
    }

    vTaskDelay(pdMS_TO_TICKS(10));
}
