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
#include "bios_menu.h"
#include "device_server.h"
#include "status_led.h"

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

// ── Audio playback queue (WS task → audio task) ───────
// WS binary callback decodes Opus and enqueues PCM frames here.
// Audio capture task dequeues and writes to speaker with portMAX_DELAY.
struct PlaybackFrame {
    int16_t samples[OPUS_FRAME_SAMPLES];  // 320 mono samples (20ms)
    int count;                             // actual sample count
};
static const size_t PLAYBACK_QUEUE_SIZE = 40;  // ~800ms buffer at 20ms/frame
static QueueHandle_t playbackQueue = nullptr;
static volatile bool playbackActive = false;  // true while audio task should drain queue
static volatile bool playbackDone = false;    // set by response:end to signal no more frames
static volatile bool playbackBuffering = true;  // jitter buffer: accumulate before playing
static int JITTER_BUFFER_FRAMES = 15;           // wait for 300ms of audio before starting

// ── Echo mode (hold-to-record, release-to-playback) ───
// Records raw stereo I2S frames to PSRAM (same as audio-pipeline test firmware).
// Plays back raw stereo directly — no mono conversion, no quality loss.
static const int ECHO_MAX_FRAMES = 500;  // 500 * 320 stereo samples = 10s @ 16kHz
static int16_t** echoFrames = nullptr;   // each frame = OPUS_FRAME_SAMPLES * 2 int16 (stereo)
static int echoFrameCount = 0;
static volatile bool echoRecording = false;
static volatile bool echoPlaying = false;

// ── Forward declarations ──────────────────────────────
static void scheduleFaceRevert(uint16_t delayMs);

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
    status_led::syncToState();
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
    else if (strcmp(event, "transcript:partial") == 0 ||
             strcmp(event, "transcript:final") == 0) {
        // STT transcript: parse {"text":"..."} or use raw data as fallback
        const char* txt = data;
        JsonDocument sttDoc;
        if (deserializeJson(sttDoc, data) == DeserializationError::Ok) {
            txt = sttDoc["text"] | data;
        }
        Serial.printf("[Main] STT: %s\n", txt);
        display::setTranscriptText("You", txt);
    }
    else if (strcmp(event, "response:start") == 0) {
        power_manager::recordInteraction();  // Wake display for response
        appState.botState = BotState::SPEAKING;
        syncFaceToState();
        cacheAccumLen = 0;
        playbackDone = false;
        playbackBuffering = true;  // accumulate frames before playing
        playbackActive = true;
        audio_io::flushSpeaker();  // Clear stale DMA data
        Serial.println("[Main] Response start — buffering audio");
    }
    else if (strcmp(event, "response:text") == 0) {
        // LLM response text: parse {"text":"...","isFinal":bool} or use raw
        const char* txt = data;
        JsonDocument respDoc;
        if (deserializeJson(respDoc, data) == DeserializationError::Ok) {
            txt = respDoc["text"] | data;
        }
        Serial.printf("[Main] LLM: %s\n", txt);
        display::setTranscriptText("Aksa", txt);
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
        // Signal the audio task to drain remaining frames, then go idle.
        // Don't set IDLE here — the audio task does it after the queue is empty.
        playbackDone = true;
        Serial.println("[Main] Response end — draining remaining audio");
    }
    else if (strcmp(event, "error") == 0) {
        Serial.printf("[Main] Error: %s\n", data);
        face::setExpression(face::Expression::SHRUG, 200);
        scheduleFaceRevert(3000);
        appState.botState = BotState::IDLE;
        // Don't call syncFaceToState() — let SHRUG play for 3s first
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
    // ── Proactive events → wake display + show content ────
    else if (strcmp(event, "proactive:reminder") == 0) {
        power_manager::recordInteraction();  // Wake display for reminder
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            display::ReminderData rd = {};
            const char* text = doc["text"] | "Reminder";
            strncpy(rd.text, text, sizeof(rd.text) - 1);
            rd.durationMs = doc["durationMs"] | 8000;
            const char* type = doc["type"] | "";
            strncpy(rd.icon, type, sizeof(rd.icon) - 1);

            // Set face expression based on reminder type (snake_case from backend)
            if (strcmp(type, "eye_break") == 0) {
                face::setExpression(face::Expression::CALM, 200);
            } else {
                face::setExpression(face::Expression::ENCOURAGING, 200);
            }

            display::showReminder(rd);
        }
    }
    else if (strcmp(event, "proactive:pomodoro") == 0) {
        power_manager::recordInteraction();  // Wake display for pomodoro
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
        power_manager::recordInteraction();  // Wake display for OTA
        status_led::showOta();
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
    // ── Face expression control from backend ─────────
    else if (strcmp(event, "face:expression") == 0) {
        // Backend/LLM sends expression based on conversation sentiment.
        // Payload: {"expression":"happy","durationMs":3000}
        // If durationMs is set, reverts to IDLE after that duration.
        // If omitted, expression persists until next state change.
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            const char* exprName = doc["expression"] | "";
            uint16_t durationMs = doc["durationMs"] | 0;

            // Map name to expression enum
            struct ExprMap { const char* name; face::Expression expr; };
            static const ExprMap map[] = {
                {"idle",        face::Expression::IDLE},
                {"listening",   face::Expression::LISTENING},
                {"thinking",    face::Expression::THINKING},
                {"speaking",    face::Expression::SPEAKING},
                {"confused",    face::Expression::CONFUSED},
                {"sleeping",    face::Expression::SLEEPING},
                {"offline",     face::Expression::OFFLINE},
                {"encouraging", face::Expression::ENCOURAGING},
                {"calm",        face::Expression::CALM},
                {"focused",     face::Expression::FOCUSED},
                {"happy",       face::Expression::HAPPY},
                {"sad",         face::Expression::SAD},
                {"shrug",       face::Expression::SHRUG},
            };

            bool found = false;
            for (const auto& m : map) {
                if (strcmp(exprName, m.name) == 0) {
                    power_manager::recordInteraction();
                    face::setExpression(m.expr, 200);
                    if (durationMs > 0) {
                        scheduleFaceRevert(durationMs);
                    }
                    Serial.printf("[Main] Face expression: %s (duration=%dms)\n", exprName, durationMs);
                    found = true;
                    break;
                }
            }
            if (!found) {
                Serial.printf("[Main] Unknown expression: %s\n", exprName);
            }
        }
    }
    // ── Config update from backend (settings changed via app) ──
    else if (strcmp(event, "config:update") == 0) {
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            // Volume — save to NVS and apply to ES8311 codec immediately
            if (doc.containsKey("volume")) {
                uint8_t vol = doc["volume"] | 80;
                nvs_store::setVolume(vol);
                audio_io::setVolume(vol);
                Serial.printf("[Main] Config: volume=%d\n", vol);
            }
            // Brightness
            if (doc.containsKey("brightness")) {
                uint8_t br = doc["brightness"] | 70;
                nvs_store::setBrightness(br);
                display::setBrightness(br);
                power_manager::Config pwrCfg;
                pwrCfg.activeBrightness = br;
                power_manager::updateConfig(pwrCfg);
                Serial.printf("[Main] Config: brightness=%d\n", br);
            }
            // Presence RSSI threshold
            if (doc.containsKey("presence_rssi_threshold")) {
                int rssi = doc["presence_rssi_threshold"] | -75;
                nvs_store::setPresenceRssiThreshold(rssi);
                presence_detector::Config presCfg;
                presCfg.rssiThreshold = rssi;
                presCfg.gracePeriodSec = nvs_store::getPresenceGracePeriodSec();
                presence_detector::init(presCfg);
                Serial.printf("[Main] Config: presence RSSI=%d\n", rssi);
            }
            // Presence grace period
            if (doc.containsKey("presence_grace_period")) {
                int grace = doc["presence_grace_period"] | 45;
                nvs_store::setPresenceGracePeriodSec(grace);
                presence_detector::Config presCfg;
                presCfg.rssiThreshold = nvs_store::getPresenceRssiThreshold();
                presCfg.gracePeriodSec = grace;
                presence_detector::init(presCfg);
                Serial.printf("[Main] Config: presence grace=%ds\n", grace);
            }
            // Audio jitter buffer (ms → frames at 20ms/frame)
            if (doc.containsKey("audio_jitter_ms")) {
                int ms = doc["audio_jitter_ms"] | 300;
                if (ms < 100) ms = 100;
                if (ms > 500) ms = 500;
                JITTER_BUFFER_FRAMES = ms / 20;
                Serial.printf("[Main] Config: jitter buffer=%dms (%d frames)\n", ms, JITTER_BUFFER_FRAMES);
            }
            // Idle animation speed
            if (doc.containsKey("idle_animation_speed")) {
                const char* speed = doc["idle_animation_speed"] | "normal";
                if (strcmp(speed, "slow") == 0) {
                    face::setIdleInterval(15000, 15000);  // 15-30s
                } else if (strcmp(speed, "fast") == 0) {
                    face::setIdleInterval(3000, 7000);    // 3-10s
                } else {
                    face::setIdleInterval(8000, 12000);   // 8-20s (default)
                }
                Serial.printf("[Main] Config: idle animation speed=%s\n", speed);
            }
            // Show transcript overlay
            if (doc.containsKey("display_transcript")) {
                bool show = doc["display_transcript"] | true;
                display::setTranscriptOverlay(show);
                Serial.printf("[Main] Config: display_transcript=%s\n", show ? "true" : "false");
            }
            // Presence detection enable/disable at runtime
            if (doc.containsKey("presence_enabled")) {
                bool enabled = doc["presence_enabled"] | false;
                nvs_store::setPresenceEnabled(enabled);
                if (enabled) {
                    ble_manager::initScanOnly();
                    ble_manager::startPresenceScan();
                    Serial.println("[Main] Config: presence scanning STARTED");
                } else {
                    ble_manager::stopPresenceScan();
                    Serial.println("[Main] Config: presence scanning STOPPED");
                }
            }
            // Idle timeout
            if (doc.containsKey("idle_timeout_seconds")) {
                int timeout = doc["idle_timeout_seconds"] | 300;
                power_manager::Config pwrCfg;
                pwrCfg.sleepTimeoutSec = timeout;
                power_manager::updateConfig(pwrCfg);
                Serial.printf("[Main] Config: idle timeout=%ds\n", timeout);
            }
        }
    }
    else {
        Serial.printf("[Main] Unknown event: %s = %s\n", event, data);
    }
}

static void onWsBinary(const uint8_t* data, size_t len) {
    // Decode Opus → PCM, then enqueue for the audio task to play.
    // This keeps the WS poll task non-blocking so it can process JSON events.
    int samples = opus_codec::decode(data, len, playbackBuffer, OPUS_FRAME_SAMPLES);
    if (samples > 0 && playbackQueue) {
        PlaybackFrame frame;
        frame.count = min(samples, (int)OPUS_FRAME_SAMPLES);
        memcpy(frame.samples, playbackBuffer, frame.count * sizeof(int16_t));

        // Non-blocking enqueue — drop frame if queue full (better than blocking WS)
        if (xQueueSend(playbackQueue, &frame, 0) != pdTRUE) {
            static uint32_t lastDropLog = 0;
            if (millis() - lastDropLog > 1000) {
                Serial.println("[Main] Playback queue full — dropping frame");
                lastDropLog = millis();
            }
        }
    }

    // Accumulate raw Opus for TTS cache
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
                appState.botState = BotState::LISTENING;
                syncFaceToState();
                if (appState.wsConnected) {
                    ws_client::sendEvent("audio:start");
                    Serial.println("[Main] Recording started (backend)");
                } else {
                    // Echo mode — allocate buffer on first use, record raw stereo
                    if (!echoFrames) {
                        echoFrames = (int16_t**)ps_malloc(ECHO_MAX_FRAMES * sizeof(int16_t*));
                        if (echoFrames) {
                            for (int i = 0; i < ECHO_MAX_FRAMES; i++) {
                                echoFrames[i] = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * 2 * sizeof(int16_t));
                            }
                        }
                        Serial.printf("[Main] Echo buffer allocated — PSRAM free: %u\n", ESP.getFreePsram());
                    }
                    echoFrameCount = 0;
                    echoRecording = true;
                    Serial.println("[Main] Recording started (echo mode)");
                }
            }
            break;

        case touch::Event::HOLD_END:
            if (appState.botState == BotState::LISTENING) {
                echoRecording = false;
                audio_io::stopMic();
                if (appState.wsConnected) {
                    appState.botState = BotState::THINKING;
                    syncFaceToState();
                    ws_client::sendEvent("audio:end");
                    Serial.println("[Main] Recording stopped, waiting for response...");
                } else {
                    // Echo mode — play back recorded audio
                    appState.botState = BotState::SPEAKING;
                    syncFaceToState();
                    echoPlaying = true;
                    Serial.printf("[Main] Echo playback — %d frames (%.1fs)\n",
                                  echoFrameCount, echoFrameCount * 0.02f);
                }
            }
            break;

        case touch::Event::TAP:
            if (appState.botState == BotState::SPEAKING) {
                // Interrupt playback — stop audio task and flush queue
                playbackActive = false;
                playbackDone = false;
                xQueueReset(playbackQueue);
                appState.interrupted = true;
                appState.botState = BotState::IDLE;
                syncFaceToState();
                ws_client::sendEvent("audio:interrupt");
                audio_io::stopSpeaker();
                face::feedAudioAmplitude(0);
                display::setTranscriptText("", "");  // Clear transcript
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
            // recordInteraction() already called at top of onTouchEvent
            appState.botState = BotState::IDLE;
            syncFaceToState();
            face::setExpression(face::Expression::HAPPY, 200);
            scheduleFaceRevert(2000);
            // Ask backend for a wake-up greeting with TTS
            if (appState.wsConnected) {
                ws_client::sendEvent("wake:touch");
            }
            Serial.println("[Main] Woke from touch");
            break;
    }
}

// ── Audio capture task (Core 0, high priority) ──────────

static bool audioInitialized = false;

static void audioCaptureLoop(void* param) {
    bool stackLogged = false;
    for (;;) {
        if (!audioInitialized) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }

        // ── Backend audio playback — drain queue with blocking I2S writes ──
        if (playbackActive && playbackQueue) {
            // Jitter buffer: wait for enough frames before starting playback.
            // This absorbs network jitter and prevents stuttery audio.
            if (playbackBuffering) {
                int queued = uxQueueMessagesWaiting(playbackQueue);
                if (queued >= JITTER_BUFFER_FRAMES || playbackDone) {
                    playbackBuffering = false;
                    Serial.printf("[Main] Jitter buffer ready — %d frames queued\n", queued);
                } else {
                    vTaskDelay(pdMS_TO_TICKS(20));
                    continue;
                }
            }

            PlaybackFrame frame;
            if (xQueueReceive(playbackQueue, &frame, pdMS_TO_TICKS(150)) == pdTRUE) {
                audio_io::writeSpeaker(frame.samples, frame.count);

                // Feed amplitude to face for mouth animation
                int32_t sum = 0;
                for (int i = 0; i < frame.count; i++) {
                    sum += abs(frame.samples[i]);
                }
                face::feedAudioAmplitude((float)sum / (frame.count * 32768.0f));
            } else if (playbackDone) {
                // Queue empty and no more frames coming — finish playback
                playbackActive = false;
                playbackDone = false;
                playbackBuffering = true;
                face::feedAudioAmplitude(0);
                appState.botState = BotState::IDLE;
                syncFaceToState();
                display::setTranscriptText("", "");  // Clear transcript overlay
                Serial.println("[Main] Playback complete");
            }
            continue;
        }

        // ── Echo playback — raw stereo, same as audio-pipeline test firmware ──
        if (echoPlaying && appState.botState == BotState::SPEAKING) {
            Serial.printf("[Echo] Playing %d frames (%.1fs)\n",
                          echoFrameCount, echoFrameCount * 0.02f);
            audio_io::flushSpeaker();

            for (int i = 0; i < echoFrameCount && echoPlaying; i++) {
                // Write raw stereo directly — no mono conversion
                audio_io::writeRawStereo(echoFrames[i], OPUS_FRAME_SAMPLES);

                // Feed amplitude to face (extract left channel for RMS)
                int32_t sum = 0;
                for (int s = 0; s < OPUS_FRAME_SAMPLES; s++) {
                    sum += abs(echoFrames[i][s * 2]);  // left channel only
                }
                face::feedAudioAmplitude((float)sum / (OPUS_FRAME_SAMPLES * 32768.0f));
            }

            // Flush silence to push out DMA buffer
            int16_t silence[OPUS_FRAME_SAMPLES * 2] = {};
            for (int i = 0; i < 3; i++) {
                audio_io::writeRawStereo(silence, OPUS_FRAME_SAMPLES);
            }

            echoPlaying = false;
            face::feedAudioAmplitude(0);
            appState.botState = BotState::IDLE;
            syncFaceToState();
            display::setTranscriptText("", "");
            Serial.println("[Echo] Playback done");
            continue;
        }

        // ── Echo recording — raw stereo to PSRAM ──
        if (echoRecording && appState.botState == BotState::LISTENING) {
            if (echoFrameCount < ECHO_MAX_FRAMES && echoFrames) {
                size_t read = audio_io::readRawStereo(echoFrames[echoFrameCount], OPUS_FRAME_SAMPLES);
                if (read > 0) echoFrameCount++;
            }
            continue;  // skip the normal capture path below
        }

        if (appState.botState != BotState::LISTENING) {
            if (recording_buffer::isBuffering()) {
                recording_buffer::stopBuffering();
            }
            stackLogged = false;
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        if (!stackLogged) {
            vTaskDelay(pdMS_TO_TICKS(60));
        }

        size_t samplesRead = audio_io::readMic(pcmBuffer, OPUS_FRAME_SAMPLES);
        if (samplesRead == 0) continue;

        // VAD: check for end-of-speech (auto-stop recording)
        vad::Result vadResult = vad::analyze(pcmBuffer, samplesRead);
        if (vadResult == vad::Result::END_OF_SPEECH && appState.wsConnected) {
            appState.botState = BotState::THINKING;
            syncFaceToState();
            ws_client::sendEvent("audio:end");
            audio_io::stopMic();
            vad::reset();
            Serial.println("[Main] VAD: end-of-speech, stopping");
            continue;
        }

        if (!stackLogged) {
            UBaseType_t hwm = uxTaskGetStackHighWaterMark(NULL);
            Serial.printf("[Audio] Stack watermark: %u bytes free\n", hwm * 4);
            stackLogged = true;
        }

        // Backend mode — encode and send via WebSocket
        int opusBytes = opus_codec::encode(pcmBuffer, opusBuffer, OPUS_MAX_FRAME_BYTES);
        if (opusBytes > 0 && appState.wsConnected) {
            ws_client::sendBinary(opusBuffer, opusBytes);
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
    // Kill backlight immediately — before any library init can draw to screen
    pinMode(LCD_BL, OUTPUT);
    digitalWrite(LCD_BL, LOW);

    Serial.begin(115200);
    delay(1000);
    Serial.println("\n=== Aksabot Firmware ===\n");

    // ── 1. Core init (logging, NVS, PSRAM) ─────────────────
    debug_log::init();
    nvs_store::init();

    pcmBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * 2 * sizeof(int16_t));
    opusBuffer = (uint8_t*)ps_malloc(OPUS_MAX_FRAME_BYTES);
    playbackBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * sizeof(int16_t));
    playbackQueue = xQueueCreate(PLAYBACK_QUEUE_SIZE, sizeof(PlaybackFrame));

    // Pre-allocate display sprite buffer in PSRAM BEFORE WiFi grabs memory.
    // WiFi RX buffers eat ~100KB of PSRAM; sprite needs 150KB. If we wait
    // until display::init(), the allocation may fail → direct draw → flicker.
    extern void* preallocSpriteBuffer;
    preallocSpriteBuffer = ps_malloc(LCD_WIDTH * LCD_HEIGHT * 2);
    Serial.printf("[Main] Sprite pre-alloc: %s (%u bytes PSRAM free)\n",
        preallocSpriteBuffer ? "OK" : "FAILED", ESP.getFreePsram());
    cacheAccumBuf = (uint8_t*)ps_malloc(CACHE_ACCUM_MAX);
    // Echo buffer allocated lazily on first use (saves ~640KB PSRAM at boot)

    if (!pcmBuffer || !opusBuffer || !playbackBuffer) {
        Serial.println("[Main] FATAL: Failed to allocate PSRAM buffers");
        while (true) { delay(1000); }
    }
    Serial.printf("[Main] PSRAM free: %u bytes\n", ESP.getFreePsram());

    // ── 2. Check if device is already configured ───────────
    bool firstBoot = nvs_store::isFirstBoot();
    bool hasNvsCreds = nvs_store::hasWifiCredentials();
    bool hasCompileCreds = (strlen(WIFI_SSID) > 0);
    bool isConfigured = hasNvsCreds || hasCompileCreds;

    // ── 2b. Start WiFi early (needs internal SRAM before other subsystems grab it)
    if (isConfigured) {
        // Debug: scan to see what networks are visible
        WiFi.mode(WIFI_STA);
        Serial.println("[Main] Scanning WiFi networks...");
        int n = WiFi.scanNetworks();
        for (int i = 0; i < n; i++) {
            Serial.printf("[WiFi Scan] %s (%d dBm)\n", WiFi.SSID(i).c_str(), WiFi.RSSI(i));
        }
        WiFi.scanDelete();
        if (n == 0) Serial.println("[WiFi Scan] No networks found!");
        Serial.printf("[Main] Target SSID: '%s'\n", WIFI_SSID);

        wifi_manager::init();
        Serial.println("[Main] WiFi started early (background connect)");
    }

    // ── 3. Display init + splash ───────────────────────────
    display::init();
    boot_screen::init();

    // Show splash and poll BOOT button (GPIO 0) during the splash delay.
    // User presses RESET to reboot, then presses BOOT during splash to enter BIOS.
    pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);
    boot_screen::showSplashWithBootCheck(FIRMWARE_VERSION);
    bool bootButtonHeld = (digitalRead(BOOT_BUTTON_PIN) == LOW);
    if (bootButtonHeld) {
        Serial.println("[Main] BOOT button pressed during splash — will enter BIOS");
    }

    // ── 5. Hardware init ───────────────────────────────────

    sd_storage::init();
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
            if (newState == PresenceState::PRESENT && oldState == PresenceState::AWAY) {
                power_manager::recordInteraction();
                // Happy greeting — user is back at desk
                face::setExpression(face::Expression::HAPPY, 200);
                scheduleFaceRevert(3000);
                if (appState.wsConnected) {
                    char payload[48];
                    snprintf(payload, sizeof(payload), "{\"awayDurationSeconds\":%u}", awaySec);
                    ws_client::sendEvent("presence:arrived", payload);
                }
            }
            else if (newState == PresenceState::AWAY) {
                if (appState.wsConnected) {
                    ws_client::sendEvent("presence:departed");
                }
                // Show sad face briefly, then sleep via power_manager
                // (don't call display::sleep() directly — keeps power_manager in sync)
                face::setExpression(face::Expression::SAD, 300);
                power_manager::setState(power_manager::PowerState::SLEEPING);
            }
        });
    }

    touch::init();
    touch::onEvent(onTouchEvent);

    audio_io::init();
    audioInitialized = true;

    bool opusOk = opus_codec::init();
    if (!opusOk) {
        Serial.println("[Main] FATAL: Opus init failed");
        while (true) { delay(1000); }
    }

    vad::init();
    ota_update::init();
    status_led::init();

    // Load brightness from NVS and pass to power manager
    {
        power_manager::Config pwrCfg;
        uint8_t savedBrightness = nvs_store::getBrightness();
        pwrCfg.activeBrightness = savedBrightness;
        display::setBrightness(savedBrightness);
        power_manager::init(pwrCfg);
    }

    // ── 6. BIOS menu (only if BOOT button was held) ───────
    bool enterSetupFromBios = false;
    if (bootButtonHeld) {
        Serial.println("[Main] Entering BIOS menu");
        enterSetupFromBios = bios_menu::show();
        Serial.printf("[Main] BIOS exit — setup WiFi: %s\n",
                       enterSetupFromBios ? "yes" : "no");
    }

    // ── 7. First-boot introduction ─────────────────────────
    if (firstBoot) {
        Serial.println("[Main] First boot detected — showing introduction");
        boot_screen::showFirstBoot();
    }

    // ── 8. Provisioning gate ──────────────────────────────
    // If no credentials: start BLE + AP for provisioning.
    // BLE is started here (before WiFi) so the Flutter app can discover the device.
    // If already configured: BLE is deferred to after WiFi connect (step 10b).
    bool needsProvisioning = enterSetupFromBios || (!hasNvsCreds && !hasCompileCreds);
    bool provisionedViaBle = false;

    if (needsProvisioning) {
        // Start BLE for provisioning — Flutter app scans for 0xFFE0 service.
        // WiFi AP is NOT started here because BLE + WiFi crash on ESP32-S3.
        // Users provision via the Aksabot app (BLE) exclusively.
        ble_manager::init();
        Serial.println("[Main] BLE started — waiting for provisioning via app");

        boot_screen::showProvisioningPrompt(nullptr);  // BLE only, no AP name

        // Poll until credentials arrive via BLE
        while (!ble_manager::isProvisioned()) {
            boot_screen::tickProvisioningAnimation(millis());
            delay(100);
        }

        provisionedViaBle = true;
        boot_screen::showProvisioningStatus("Credentials received via Bluetooth!");
        Serial.println("[Main] Provisioned via BLE");
        delay(600);

        // Stop BLE advertising before WiFi starts (coexistence)
        ble_manager::stopAdvertising();
    } else if (hasNvsCreds) {
        Serial.println("[Main] Using NVS WiFi credentials");
    } else {
        Serial.println("[Main] Using compile-time WiFi credentials");
    }

    // ── 10. Start face UI immediately ───────────────────────
    // Show face immediately. If just provisioned, show THINKING (loading)
    // instead of OFFLINE — the setup is still in progress, not broken.
    if (isConfigured) {
        appState.botState = BotState::IDLE;
    } else if (provisionedViaBle) {
        appState.botState = BotState::THINKING;  // setup in progress, not offline
    } else {
        appState.botState = BotState::OFFLINE;
    }
    syncFaceToState();
    updateStatusBar();

    // Init WS client early (creates internal state) — but don't connect yet
    ws_client::init(onWsJson, onWsBinary);

    xTaskCreatePinnedToCore(displayLoop, "display", 6144, nullptr, 3, &displayTask, 1);
    xTaskCreatePinnedToCore(audioCaptureLoop, "audio_cap", 24576, nullptr, 5, &audioCaptureTask, 0);
    xTaskCreatePinnedToCore(wsLoop, "ws_poll", 8192, nullptr, 3, &wsTask, 1);
    Serial.println("[Main] Face UI active — FreeRTOS tasks started");

    // ── 11. WiFi connect ─────────────────────────────────
    // Start WiFi if not already started in step 2b.
    // After BLE provisioning, credentials are in NVS but WiFi was never inited.
    if (!isConfigured || provisionedViaBle) {
        wifi_manager::init();
    }

    if (needsProvisioning) {
        // First boot — show connecting screen since user is watching
        char ssidBuf[64] = {};
        const char* ssidDisplay = WIFI_SSID;
        if (nvs_store::getWifiSsid(ssidBuf, sizeof(ssidBuf)) && strlen(ssidBuf) > 0) {
            ssidDisplay = ssidBuf;
        }
        boot_screen::showConnecting(ssidDisplay);
    }

    Serial.println("[Main] Waiting for Wi-Fi...");
    wifi_manager::waitForConnection(15000);

    if (wifi_manager::isConnected()) {
        Serial.println("[Main] WiFi connected");
        appState.wifiConnected = true;
        appState.botState = BotState::IDLE;
        syncFaceToState();
        updateStatusBar();

        if (MDNS.begin("aksabot")) {
            MDNS.addService("aksabot", "tcp", 80);
        }

        if (firstBoot) {
            nvs_store::markSetupComplete();
        }
        // Keep setup mode open until a token is received — allows the app
        // to deliver the token at any point (not just on first boot).
        bool hasToken = nvs_store::hasDeviceToken() || (strlen(DEVICE_TOKEN) > 0);
        if (!hasToken) {
            device_server::setSetupMode(true);
        }
        device_server::start(FIRMWARE_VERSION);
    } else {
        Serial.println("[Main] WiFi failed — offline mode");
        appState.botState = BotState::OFFLINE;
        syncFaceToState();
        updateStatusBar();

        // Show user-visible error so they know what to do
        display::ReminderData rd = {};
        strncpy(rd.text, "Can't connect to WiFi. Check your network and restart.", sizeof(rd.text) - 1);
        rd.durationMs = 10000;
        strncpy(rd.icon, "error", sizeof(rd.icon) - 1);
        display::showReminder(rd);
    }

    // ── 12. WebSocket connect ──────────────────────────────
    bool hasToken = nvs_store::hasDeviceToken() || (strlen(DEVICE_TOKEN) > 0);
    if (wifi_manager::isConnected() && hasToken) {
        Serial.println("[Main] Device token found — connecting to backend");
        ws_client::connect();
    } else if (wifi_manager::isConnected() && !hasToken) {
        Serial.println("[Main] No device token — waiting for app to complete setup");
        // Show thinking/loading face while the app automatically registers
        // and sends the token. No user action needed.
        face::setExpression(face::Expression::THINKING, 200);
    }

    // ── 13. BLE presence scanning ──────────────────────────
    // NimBLE passive scanning coexists with WiFi on ESP32-S3.
    // If BLE was already inited for provisioning, initScanOnly() is a no-op.
    if (nvs_store::getPresenceEnabled()) {
        ble_manager::initScanOnly();
        ble_manager::startPresenceScan();
        Serial.println("[Main] BLE presence scanning started");
    } else {
        Serial.println("[Main] BLE presence scanning disabled (enable in app settings)");
    }

    Serial.println("\n[Main] Boot complete.\n");
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

    // Handle app commands via local HTTP
    if (device_server::consumeReconnect()) {
        Serial.println("[Main] App requested reconnect");
        if (wifi_manager::isConnected()) {
            ws_client::reconnectWithToken();
            appState.botState = BotState::IDLE;
            syncFaceToState();
            updateStatusBar();
        }
    }
    if (device_server::consumeWake()) {
        Serial.println("[Main] App requested wake");
        power_manager::recordInteraction();
        appState.botState = BotState::IDLE;
        syncFaceToState();
    }

    // Check if device token was received via HTTP → connect to backend
    if (device_server::consumeNewToken() && wifi_manager::isConnected()) {
        Serial.println("[Main] New device token received — connecting to backend WS");
        ws_client::reconnectWithToken();
        ble_manager::notifyAuthStatus(1);  // 1 = token stored

        // Reset from confused/offline face to idle — setup is complete
        appState.botState = BotState::IDLE;
        syncFaceToState();
        updateStatusBar();

        // Dismiss any lingering reminder ("Almost there...")
        display::setMode(display::Mode::FACE);
    }

    // Tick presence detector + BLE scanner
    presence_detector::tick(now);
    ble_manager::tickPresenceScan(now);

    // Tick power management and status LED
    power_manager::tick(now);
    status_led::tick(now);

    // Sync connectivity state — check actual WiFi, not just our flag
    bool wifiNow = wifi_manager::isConnected();
    if (wifiNow && !appState.wifiConnected) {
        appState.wifiConnected = true;
        bool hasToken = nvs_store::hasDeviceToken() || (strlen(DEVICE_TOKEN) > 0);
        if (hasToken && !appState.wsConnected) {
            ws_client::connect();
            Serial.println("[Main] WiFi recovered — connecting WS");
        }
    } else if (!wifiNow && appState.wifiConnected) {
        appState.wifiConnected = false;
    }

    BotState prevState = appState.botState;
    if (!appState.wifiConnected && appState.botState != BotState::OFFLINE &&
        appState.botState != BotState::LISTENING && appState.botState != BotState::SPEAKING &&
        appState.botState != BotState::THINKING) {
        appState.botState = BotState::OFFLINE;
    } else if (appState.wifiConnected && appState.botState == BotState::OFFLINE) {
        appState.botState = BotState::IDLE;
    }

    if (appState.botState != prevState) {
        syncFaceToState();
    }

    // Throttle status bar updates — only refresh when connectivity actually changes
    static bool prevWifi = false;
    static bool prevWs = false;
    if (appState.wifiConnected != prevWifi || appState.wsConnected != prevWs) {
        // WS just connected — send device info and ensure face is IDLE
        if (appState.wsConnected && !prevWs) {
            appState.botState = BotState::IDLE;
            syncFaceToState();

            // Report device info to backend
            char infoPayload[128];
            snprintf(infoPayload, sizeof(infoPayload),
                "{\"firmwareVersion\":\"%s\",\"wifiSsid\":\"%s\",\"wifiRssi\":%d}",
                FIRMWARE_VERSION, WiFi.SSID().c_str(), WiFi.RSSI());
            ws_client::sendEvent("device:info", infoPayload);
        }
        prevWifi = appState.wifiConnected;
        prevWs = appState.wsConnected;
        updateStatusBar();
        status_led::syncToState();
    }

    vTaskDelay(pdMS_TO_TICKS(10));
}
