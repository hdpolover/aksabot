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
#include "face_style.h"
#include "touch.h"
#include "vad.h"
#include "ota_update.h"
#include "debug_log.h"
#include "power_manager.h"
#include "ble_manager.h"
#include <NimBLEDevice.h>
#include "boot_screen.h"
#include "bios_menu.h"
#include "device_server.h"
#include "status_led.h"
#include "wake_word.h"
#include "gesture.h"
#include "ui_audio.h"
#include "emotion_audio.h"
#include "sfx_audio.h"

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
static volatile uint32_t handsFreeRecordStartMs = 0;  // when hands-free recording started (for no-speech timeout)
static volatile bool playbackBuffering = true;  // jitter buffer: accumulate before playing
static volatile bool pendingSttFailAudio = false;  // set by audio task (Core 0), played by main loop (Core 1)
static int JITTER_BUFFER_FRAMES = 15;           // wait for 300ms of audio before starting
static volatile uint32_t lastFrameReceivedMs = 0;  // starvation detection

// ── Speaker stop flag (cross-task safe) ───────────────
// NEVER call audio_io::stopSpeaker() / flushSpeaker() directly from the WS task
// (Core 1) while the audio task (Core 0) may be blocking in i2s_channel_write().
// ESP-IDF prohibits i2s_channel_disable() while i2s_channel_write() is active —
// it corrupts the I2S peripheral state and produces the audible glitch/overlap.
// Instead, set this flag; the audio task calls stopSpeaker() from Core 0 safely.
static volatile bool stopSpeakerPending = false;

// ── Multi-response sequencing ─────────────────────────
// When the backend sends two responses back-to-back (e.g. reconnect greeting +
// morning briefing), the firmware receives two response:start / response:end pairs.
// The first response:end must NOT set playbackDone=true while the second response
// is still streaming — that would cut the second response short.
// pendingResponseEnds counts unmatched response:start events. response:end only
// sets playbackDone=true when the count reaches zero (all responses done).
static volatile int8_t pendingResponseEnds = 0;

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
    sb.blePresent = (appState.presenceState == PresenceState::PRESENT ||
                     appState.presenceState == PresenceState::LEAVING);
    sb.blePresenceEnabled = nvs_store::getPresenceEnabled();
    // Stall detection: speaking/thinking but no data flowing for 3+ seconds
    sb.connectionStalled = false;
    if (appState.botState == BotState::SPEAKING && playbackActive && !playbackDone) {
        sb.connectionStalled = (millis() - lastFrameReceivedMs) > 3000;
    } else if (appState.botState == BotState::THINKING) {
        // In thinking state, we expect response:start within reasonable time
        // (stuckCheckMs tracks when we entered the state)
        // No extra stall flag here — the thinking dots already indicate waiting
    }
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
        display::setTranscriptText(txt);
    }
    else if (strcmp(event, "audio:cancel") == 0) {
        // Backend superseded this pipeline with a new one — flush everything immediately.
        playbackActive       = false;
        playbackDone         = false;
        playbackBuffering    = true;
        pendingResponseEnds  = 0;
        xQueueReset(playbackQueue);
        stopSpeakerPending   = true;  // audio task will call stopSpeaker() safely
        face::feedAudioAmplitude(0);
        display::setTranscriptText("");
        if (appState.botState == BotState::SPEAKING ||
            appState.botState == BotState::THINKING) {
            appState.botState = BotState::IDLE;
            syncFaceToState();
            wake_word::startListening();
        }
        Serial.println("[Main] audio:cancel — flushed pending response");
    }
    else if (strcmp(event, "response:start") == 0) {
        power_manager::recordInteraction();  // Wake display for response

        // If already playing, flush the old playback.
        // pendingResponseEnds is NOT reset here — the old response:end will still
        // arrive and must be counted down before playbackDone is set.
        if (playbackActive) {
            playbackActive = false;
            xQueueReset(playbackQueue);
            face::feedAudioAmplitude(0);
            // Signal audio task to call stopSpeaker() from Core 0.
            // Calling i2s_channel_disable() from Core 1 while Core 0 is blocking
            // in i2s_channel_write() violates the ESP-IDF API and glitches audio.
            stopSpeakerPending = true;
            Serial.println("[Main] Flushing previous playback for new response");
        }

        pendingResponseEnds++;  // This response:start will produce exactly one response:end

        appState.botState = BotState::SPEAKING;
        syncFaceToState();
        cacheAccumLen = 0;
        playbackDone = false;
        playbackBuffering = true;  // accumulate frames before playing
        playbackActive = true;
        lastFrameReceivedMs = millis();  // Init starvation timer
        Serial.printf("[Main] Response start — buffering audio (pending ends: %d)\n", (int)pendingResponseEnds);
    }
    else if (strcmp(event, "response:text") == 0) {
        // LLM response text: parse {"text":"...","isFinal":bool} or use raw
        const char* txt = data;
        JsonDocument respDoc;
        if (deserializeJson(respDoc, data) == DeserializationError::Ok) {
            txt = respDoc["text"] | data;
        }
        Serial.printf("[Main] LLM: %s\n", txt);
        display::setTranscriptText(txt);
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

        pendingResponseEnds--;
        if (pendingResponseEnds <= 0) {
            // All queued responses have ended — signal the audio task to drain
            // remaining frames then go idle.
            pendingResponseEnds = 0;
            playbackDone = true;
            Serial.println("[Main] Response end — draining remaining audio");
        } else {
            // More responses are still coming (multi-response sequence).
            // Don't set playbackDone yet — current response is still the last one.
            Serial.printf("[Main] Response end (intermediate, %d still pending)\n", (int)pendingResponseEnds);
        }
    }
    else if (strcmp(event, "error") == 0) {
        Serial.printf("[Main] Error: %s\n", data);
        resilience_audio::playClip(resilience_audio::Clip::ERROR);
        face::setExpression(face::Expression::SHRUG, 200);
        scheduleFaceRevert(3000);
        appState.botState = BotState::IDLE;
        display::setTranscriptText("");  // Clear stuck transcript
        // Don't call syncFaceToState() — let SHRUG play for 3s first
    }
    else if (strcmp(event, "state:update") == 0) {
        // Backend state sync (e.g., after STT error resets to idle).
        // IMPORTANT: never override LISTENING — the user may have pressed PTT
        // while the error clip was playing (blocking the WS task for ~2s).
        // When the clip finishes and the WS task drains buffered messages, a
        // stale state:update:idle would cancel the in-progress recording,
        // causing only 1 audio chunk to reach the backend and no audio:end.
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            const char* state = doc["state"] | "";
            if (strcmp(state, "idle") == 0
                && appState.botState != BotState::IDLE
                && appState.botState != BotState::LISTENING) {
                Serial.println("[Main] Backend reset to idle");
                appState.botState = BotState::IDLE;
                syncFaceToState();
                display::setTranscriptText("");
            }
        }
    }
    // ── Proactive events → wake display + show content ────
    else if (strcmp(event, "proactive:reminder") == 0) {
        power_manager::recordInteraction();  // Wake display for reminder
        ui_audio::play(ui_audio::Clip::NOTIFICATION);
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
                display::setMode(display::getHomeMode());
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
    // ── Context sync (time + weather from backend) ────
    else if (strcmp(event, "context:sync") == 0) {
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            display::GlanceData gd = {};
            const char* t = doc["time"] | "";
            const char* d = doc["date"] | "";
            strncpy(gd.time, t, sizeof(gd.time) - 1);
            strncpy(gd.date, d, sizeof(gd.date) - 1);

            if (!doc["weather"].isNull()) {
                const char* w = doc["weather"] | "";
                strncpy(gd.weather, w, sizeof(gd.weather) - 1);
                gd.temp = doc["temp"] | 0;
                gd.humidity = doc["humidity"] | 0;
                gd.weatherCode = doc["weatherCode"] | 0;
                gd.hasWeather = true;
            }

            display::updateContextData(gd);
            Serial.printf("[Main] Context sync: %s, %s%s%d°C\n",
                gd.time, gd.date,
                gd.hasWeather ? ", " : "",
                gd.hasWeather ? gd.temp : 0);
        }
    }
    // ── Face expression control from backend ─────────
    else if (strcmp(event, "face:expression") == 0) {
        // Backend/LLM sends expression based on conversation sentiment.
        // Payload: {"expression":"happy","durationMs":3000,"withSound":false}
        // withSound:true  — standalone trigger (presence, proactive) → play emotion clip
        // withSound:false — pipeline sentence (TTS follows immediately) → face only
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            const char* exprName = doc["expression"] | "";
            uint16_t durationMs = doc["durationMs"] | 0;
            bool withSound = doc["withSound"] | false;

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
                    if (withSound) {
                        emotion_audio::play(exprName);
                    }
                    Serial.printf("[Main] Face expression: %s (sound=%d duration=%dms)\n",
                        exprName, (int)withSound, durationMs);
                    found = true;
                    break;
                }
            }
            if (!found) {
                Serial.printf("[Main] Unknown expression: %s\n", exprName);
            }
        }
    }
    // ── SFX clip from backend LLM [sfx:clipname] tags ────
    else if (strcmp(event, "audio:sfx") == 0) {
        // Payload: {"clip":"rimshot"}
        // Backend extracts [sfx:xxx] tags from LLM text and sends this event
        // before the TTS frames for that sentence, so the clip plays first.
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            const char* clipName = doc["clip"] | "";
            if (clipName && *clipName) {
                Serial.printf("[Main] SFX: %s\n", clipName);
                sfx_audio::play(clipName);
            }
        }
    }
    // ── Config update from backend (settings changed via app) ──
    else if (strcmp(event, "config:update") == 0) {
        JsonDocument doc;
        if (deserializeJson(doc, data) == DeserializationError::Ok) {
            // Volume — save to NVS and apply to ES8311 codec immediately
            if (!doc["volume"].isNull()) {
                uint8_t vol = doc["volume"] | 80;
                nvs_store::setVolume(vol);
                audio_io::setVolume(vol);
                Serial.printf("[Main] Config: volume=%d\n", vol);
            }
            // Brightness
            if (!doc["brightness"].isNull()) {
                uint8_t br = doc["brightness"] | 70;
                nvs_store::setBrightness(br);
                display::setBrightness(br);
                power_manager::Config pwrCfg;
                pwrCfg.activeBrightness = br;
                power_manager::updateConfig(pwrCfg);
                Serial.printf("[Main] Config: brightness=%d\n", br);
            }
            // Presence RSSI threshold — saved for NVS persistence (used by app)
            if (!doc["presence_rssi_threshold"].isNull()) {
                int rssi = doc["presence_rssi_threshold"] | -75;
                nvs_store::setPresenceRssiThreshold(rssi);
            }
            // Presence grace period — saved for NVS persistence (used by app)
            if (!doc["presence_grace_period"].isNull()) {
                int grace = doc["presence_grace_period"] | 45;
                nvs_store::setPresenceGracePeriodSec(grace);
            }
            // Audio jitter buffer (ms → frames at 20ms/frame)
            if (!doc["audio_jitter_ms"].isNull()) {
                int ms = doc["audio_jitter_ms"] | 300;
                if (ms < 100) ms = 100;
                if (ms > 500) ms = 500;
                JITTER_BUFFER_FRAMES = ms / 20;
                Serial.printf("[Main] Config: jitter buffer=%dms (%d frames)\n", ms, JITTER_BUFFER_FRAMES);
            }
            // Idle animation speed
            if (!doc["idle_animation_speed"].isNull()) {
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
            // Idle display mode — what the screen shows at rest ("face", "clock", "status")
            if (!doc["idle_display_mode"].isNull()) {
                const char* mode = doc["idle_display_mode"] | "face";
                display::Mode dm = display::Mode::FACE;
                if (strcmp(mode, "clock") == 0)       dm = display::Mode::CLOCK;
                else if (strcmp(mode, "status") == 0) dm = display::Mode::STATUS;
                display::setHomeMode(dm);  // sets g_homeMode + switches immediately
                nvs_store::setIdleDisplayMode(mode);
                Serial.printf("[Main] Config: idle_display_mode=%s\n", mode);
            }
            // Face style — "orbit" (circle eyes) or "nova" (rounded rect eyes)
            if (!doc["face_style"].isNull()) {
                const char* styleName = doc["face_style"] | "nova";
                const face_style::FaceStyleDef* style = face_style::fromName(styleName);
                display::setFaceStyle(static_cast<uint8_t>(style->id));
                nvs_store::setFaceStyle(static_cast<uint8_t>(style->id));
                Serial.printf("[Main] Config: face_style=%s\n", styleName);
            }
            // Show transcript overlay
            if (!doc["display_transcript"].isNull()) {
                bool show = doc["display_transcript"] | true;
                display::setTranscriptOverlay(show);
                nvs_store::setDisplayTranscript(show);
                Serial.printf("[Main] Config: display_transcript=%s\n", show ? "true" : "false");
            }
            // Presence detection enable/disable — saved to NVS, start/stop BLE advertising
            if (!doc["presence_enabled"].isNull()) {
                bool enabled = doc["presence_enabled"] | false;
                nvs_store::setPresenceEnabled(enabled);
                if (enabled) {
                    ble_manager::startPresenceAdvertising();
                    // Restore last known state so the dot is correct immediately
                    if (nvs_store::getPresencePresent()) {
                        appState.presenceState = PresenceState::PRESENT;
                    }
                } else {
                    ble_manager::stopAdvertising();
                    appState.presenceState = PresenceState::UNKNOWN;
                    nvs_store::setPresencePresent(false);  // Clear on disable
                }
                updateStatusBar();
                Serial.printf("[Main] Config: presence_enabled=%s\n", enabled ? "true" : "false");
            }
            // Idle timeout
            if (!doc["idle_timeout_seconds"].isNull()) {
                int timeout = doc["idle_timeout_seconds"] | 300;
                power_manager::Config pwrCfg;
                pwrCfg.sleepTimeoutSec = timeout;
                power_manager::updateConfig(pwrCfg);
                Serial.printf("[Main] Config: idle timeout=%ds\n", timeout);
            }
        }
    }
    // ── Presence events (sent BY backend, triggered by app BLE scan) ──
    else if (strcmp(event, "presence:arrived") == 0) {
        appState.presenceState = PresenceState::PRESENT;
        nvs_store::setPresencePresent(true);  // Persist so dot is solid after reboot
        updateStatusBar();  // Switch dot from blinking to solid
        power_manager::recordInteraction();
        Serial.println("[Presence] User arrived (app-driven)");
        ui_audio::play(ui_audio::Clip::PRESENCE_ARRIVED);
        face::setExpression(face::Expression::HAPPY, 200);
        scheduleFaceRevert(3000);
    }
    else if (strcmp(event, "presence:departed") == 0) {
        appState.presenceState = PresenceState::AWAY;
        nvs_store::setPresencePresent(false);  // Persist departure
        updateStatusBar();  // Switch dot back to blinking
        Serial.println("[Presence] User departed (app-driven)");
        ui_audio::play(ui_audio::Clip::PRESENCE_DEPARTED);
        // Run departure animation in a one-shot task
        xTaskCreate([](void*) {
            face::setExpression(face::Expression::SAD, 300);
            vTaskDelay(pdMS_TO_TICKS(800));
            face::setExpression(face::Expression::CALM, 600);
            vTaskDelay(pdMS_TO_TICKS(900));
            face::triggerYawn();
            vTaskDelay(pdMS_TO_TICKS(3200));
            face::setExpression(face::Expression::SLEEPING, 800);
            vTaskDelay(pdMS_TO_TICKS(1500));
            power_manager::setState(power_manager::PowerState::SLEEPING);
            vTaskDelete(nullptr);
        }, "departure_anim", 2048, nullptr, 1, nullptr);
    }
    // ── Remote re-provisioning request ───────────────────
    else if (strcmp(event, "device:provision") == 0) {
        Serial.println("[Main] device:provision received — rebooting to setup mode");
        // Persist the flag so the next boot skips the credentials check and
        // runs the full BLE provisioning flow instead.
        nvs_store::setForceProvision(true);
        // Show a clear, centered message on the ESP32 screen before reboot.
        power_manager::recordInteraction();
        boot_screen::showRebootingForSetup();
        // Brief pause so the user can read the screen before restart.
        vTaskDelay(pdMS_TO_TICKS(1500));
        esp_restart();
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

        // Try to enqueue with a short wait — gives audio task time to drain
        if (xQueueSend(playbackQueue, &frame, pdMS_TO_TICKS(50)) != pdTRUE) {
            // Still full after 50ms — drop oldest frame to make room
            PlaybackFrame discard;
            xQueueReceive(playbackQueue, &discard, 0);
            xQueueSend(playbackQueue, &frame, 0);
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
        case touch::Event::HOLD_START: {
            // Accept in four situations:
            //   1. IDLE          — normal push-to-talk start
            //   2. LISTENING (hands-free) — override wake-word/gesture session with PTT
            //   3. SPEAKING      — interrupt response and start speaking immediately
            //   4. THINKING      — cancel pending response and start speaking immediately
            bool wasHandsFree = (appState.botState == BotState::LISTENING &&
                                 appState.listenTrigger != ListenTrigger::TOUCH);
            bool wasActive    = (appState.botState == BotState::SPEAKING ||
                                 appState.botState == BotState::THINKING);

            if (appState.botState == BotState::IDLE || wasHandsFree || wasActive) {
                // Play before mic opens so the chime isn't captured
                ui_audio::play(ui_audio::Clip::HOLD_START);

                // Tear down whatever was in progress before starting PTT
                if (wasActive) {
                    if (appState.botState == BotState::SPEAKING) {
                        playbackActive = false;
                        playbackDone   = false;
                        xQueueReset(playbackQueue);
                        audio_io::stopSpeaker();
                        face::feedAudioAmplitude(0);
                        display::setTranscriptText("");
                    }
                    appState.interrupted = true;
                    ws_client::sendEvent("audio:interrupt");
                    Serial.println("[Main] Interrupted by hold — starting PTT");
                }

                // If overriding a hands-free session, restore default VAD
                if (wasHandsFree) {
                    vad::reset();
                    vad::init();
                    Serial.println("[Main] Overriding hands-free → push-to-talk");
                }

                appState.listenTrigger = ListenTrigger::TOUCH;
                appState.botState      = BotState::LISTENING;
                syncFaceToState();
                wake_word::stopListening();
                if (appState.wsConnected) {
                    // hands-free already sent audio:start; all other paths need it
                    if (!wasHandsFree) {
                        ws_client::sendEvent("audio:start");
                    }
                    Serial.println("[Main] Recording started (PTT)");
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
                    echoRecording  = true;
                    Serial.println("[Main] Recording started (echo mode)");
                }
            }
            break;
        }

        case touch::Event::HOLD_END:
            if (appState.botState == BotState::LISTENING) {
                echoRecording = false;
                audio_io::stopMic();
                if (appState.wsConnected) {
                    ui_audio::play(ui_audio::Clip::RECORDING_STOP);
                    resilience_audio::playClip(resilience_audio::Clip::THINKING);
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
            if (appState.botState == BotState::SPEAKING ||
                appState.botState == BotState::THINKING) {
                // Interrupt — stop whatever is happening and show confusion.
                // Playback-specific teardown only applies when actually speaking.
                if (appState.botState == BotState::SPEAKING) {
                    playbackActive      = false;
                    playbackDone        = false;
                    pendingResponseEnds = 0;
                    xQueueReset(playbackQueue);
                    stopSpeakerPending  = true;  // audio task calls stopSpeaker() safely
                    face::feedAudioAmplitude(0);
                    display::setTranscriptText("");
                }
                appState.interrupted = true;
                appState.botState    = BotState::IDLE;
                ws_client::sendEvent("audio:interrupt");
                face::setExpression(face::Expression::CONFUSED, 200);
                scheduleFaceRevert(2000);
                wake_word::startListening();  // resume — won't go through normal playback path
                Serial.println("[Main] Interrupted by tap");
            }
            else if (display::getMode() == display::Mode::REMINDER) {
                // Dismiss reminder
                display::setMode(display::getHomeMode());
                ws_client::sendEvent("proactive:dismiss");
            }
            else if (appState.botState == BotState::IDLE) {
                ui_audio::play(ui_audio::Clip::TAP);
                // Idle tap — cycle through a sequence of fun/reactive expressions
                static const face::Expression TAP_POOL[] = {
                    face::Expression::SURPRISED,
                    face::Expression::HAPPY,
                    face::Expression::SHOCKED,
                    face::Expression::ANGRY,
                    face::Expression::CONFUSED,
                    face::Expression::DISTURBED,
                    face::Expression::ENCOURAGING,
                    face::Expression::SHRUG,
                };
                static const uint8_t TAP_POOL_LEN = sizeof(TAP_POOL) / sizeof(TAP_POOL[0]);
                // Pick randomly, but avoid repeating the same expression twice in a row
                static uint8_t lastTapIdx = 0xFF;
                uint8_t pick;
                do { pick = esp_random() % TAP_POOL_LEN; } while (pick == lastTapIdx);
                lastTapIdx = pick;

                face::setExpression(TAP_POOL[pick], 150);
                scheduleFaceRevert(2800);
                Serial.printf("[Main] Idle tap — expression %d\n", (int)TAP_POOL[pick]);
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

        case touch::Event::WAKE: {
            // recordInteraction() already called at top of onTouchEvent
            resilience_audio::playClip(resilience_audio::Clip::WAKE);
            appState.botState = BotState::IDLE;
            syncFaceToState();
            // Varied wake expressions — not always happy
            static const face::Expression wakeExprs[] = {
                face::Expression::HAPPY,
                face::Expression::HAPPY,
                face::Expression::ENCOURAGING,
                face::Expression::CONFUSED,      // startled
                face::Expression::SHRUG,         // "what? huh?"
                face::Expression::CALM,          // sleepy zen
            };
            face::Expression wakeExpr = wakeExprs[esp_random() % 6];
            face::setExpression(wakeExpr, 200);
            scheduleFaceRevert(2000);
            // Ask backend for a wake-up greeting with TTS
            if (appState.wsConnected) {
                ws_client::sendEvent("wake:touch");
            }
            Serial.println("[Main] Woke from touch");
            break;
        }
    }
}

// ── Hands-free recording (wake word / gesture) ──────────

/// Start a hands-free recording session.
/// Unlike push-to-talk, the user doesn't hold the screen — VAD handles end-of-speech.
static void startHandsFreeRecording(ListenTrigger trigger) {
    if (appState.botState != BotState::IDLE) {
        Serial.printf("[Main] Hands-free ignored — bot not idle (state=%d)\n",
                      (int)appState.botState);
        return;
    }
    if (!appState.wsConnected) {
        Serial.println("[Main] Hands-free ignored — WebSocket not connected");
        return;
    }

    appState.listenTrigger = trigger;
    appState.botState = BotState::LISTENING;
    syncFaceToState();
    power_manager::recordInteraction();

    // Stop wake word listening while recording (avoid echo trigger)
    wake_word::stopListening();

    handsFreeRecordStartMs = millis();

    // Configure VAD for hands-free mode:
    // - Lower energy threshold to match this mic's signal level
    // - Shorter silence detection: 35 frames = 0.7s (push-to-talk uses HOLD_END instead)
    vad::reset();
    vad::setSilenceFrames(35);
    // Re-init with lower threshold — mic RMS during speech is ~0.002-0.005
    vad::init(vad::Config{
        .energyThreshold = 0.002f,
        .zcrThresholdLow = 0.05f,
        .zcrThresholdHigh = 0.35f,
        .silenceFramesForEnd = 35,
        .speechFramesForStart = 3,
        .adaptiveRate = 0.02f,  // Faster adaptation for hands-free
    });

    // Play a short chime or visual cue so user knows bot is listening
    face::setExpression(face::Expression::LISTENING, 150);

    ws_client::sendEvent("audio:start");
    Serial.printf("[Main] Hands-free recording started (trigger=%s)\n",
                  trigger == ListenTrigger::WAKE_WORD ? "wake_word" : "gesture");
}

/// Called by VAD END_OF_SPEECH during hands-free mode.
/// For push-to-talk, HOLD_END handles this instead.
static void onHandsFreeEndOfSpeech() {
    if (appState.botState != BotState::LISTENING) return;
    if (appState.listenTrigger == ListenTrigger::TOUCH) return;  // PTT handles its own end

    audio_io::stopMic();
    appState.botState = BotState::THINKING;
    syncFaceToState();
    ws_client::sendEvent("audio:end");
    Serial.println("[Main] Hands-free recording ended (VAD end-of-speech)");
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

        // ── Safe speaker stop ─────────────────────────────────────────────
        // stopSpeakerPending is set by the WS task (Core 1) when it needs to flush
        // the speaker. We call stopSpeaker() here (Core 0) to avoid calling
        // i2s_channel_disable() concurrently with a blocking i2s_channel_write().
        if (stopSpeakerPending) {
            stopSpeakerPending = false;
            audio_io::stopSpeaker();
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
                    // Starvation: if no frames arrive within 8s of response:start, abort.
                    // Uses lastFrameReceivedMs which is reset to millis() in the
                    // response:start handler — always fresh at the start of each session.
                    // (Old approach used a static local that was never reset on success,
                    //  causing immediate starvation on every conversation after the first.)
                    if ((millis() - lastFrameReceivedMs) > 8000) {
                        Serial.println("[Main] Playback starvation — no frames received in 8s, aborting");
                        playbackActive      = false;
                        playbackDone        = false;
                        playbackBuffering   = true;
                        pendingResponseEnds = 0;
                        face::feedAudioAmplitude(0);
                        appState.botState = BotState::IDLE;
                        syncFaceToState();
                        display::setTranscriptText("");
                    }
                    vTaskDelay(pdMS_TO_TICKS(20));
                    continue;
                }
            }

            PlaybackFrame frame;
            if (xQueueReceive(playbackQueue, &frame, pdMS_TO_TICKS(150)) == pdTRUE) {
                audio_io::writeSpeaker(frame.samples, frame.count);
                lastFrameReceivedMs = millis();  // Track last successful frame

                // Feed amplitude to face for mouth animation
                int32_t sum = 0;
                for (int i = 0; i < frame.count; i++) {
                    sum += abs(frame.samples[i]);
                }
                face::feedAudioAmplitude((float)sum / (frame.count * 32768.0f));
            } else if (playbackDone) {
                // Queue empty and no more frames coming — finish playback
                playbackActive      = false;
                playbackDone        = false;
                playbackBuffering   = true;
                pendingResponseEnds = 0;
                face::feedAudioAmplitude(0);
                appState.botState = BotState::IDLE;
                syncFaceToState();
                display::setTranscriptText("");  // Clear transcript overlay
                vad::init();  // Restore default VAD config for push-to-talk
                wake_word::startListening();  // Resume wake word detection
                Serial.println("[Main] Playback complete");
            } else if (!playbackDone && (millis() - lastFrameReceivedMs) > 5000) {
                // Queue empty for 5s but response:end never came — connection stalled
                Serial.println("[Main] Playback starvation mid-speech — aborting");
                playbackActive      = false;
                playbackDone        = false;
                playbackBuffering   = true;
                pendingResponseEnds = 0;
                face::feedAudioAmplitude(0);
                appState.botState = BotState::IDLE;
                syncFaceToState();
                display::setTranscriptText("");
                wake_word::startListening();  // Resume wake word detection
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
            display::setTranscriptText("");
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

#if HANDS_FREE_ENABLED
            // Wake word detection — read mic while idle and check for wake phrase
            if (appState.botState == BotState::IDLE && wake_word::isListening()) {
                size_t read = audio_io::readMic(pcmBuffer, OPUS_FRAME_SAMPLES);
                if (read > 0) {
                    wake_word_processMicFrame(pcmBuffer, read);
                }
                vTaskDelay(pdMS_TO_TICKS(1));
            } else {
                vTaskDelay(pdMS_TO_TICKS(10));
            }
#else
            // Hands-free disabled — don't drain the mic in idle. The I2S DMA ring
            // buffer wraps naturally (~400ms), so when PTT fires the backlog is small.
            vTaskDelay(pdMS_TO_TICKS(50));
#endif
            continue;
        }

        if (!stackLogged) {
            vTaskDelay(pdMS_TO_TICKS(60));
        }

        size_t samplesRead = audio_io::readMic(pcmBuffer, OPUS_FRAME_SAMPLES);
        if (samplesRead == 0) {
            // I2S returned nothing — small yield so IDLE0 can run if this persists.
            vTaskDelay(pdMS_TO_TICKS(5));
            continue;
        }

        // VAD: check for end-of-speech (auto-stop recording)
        vad::Result vadResult = vad::analyze(pcmBuffer, samplesRead);

        // Hands-free: abort if no speech detected within 4 seconds (false trigger)
        if (appState.listenTrigger != ListenTrigger::TOUCH && !vad::hasSpeechStarted()) {
            if ((millis() - handsFreeRecordStartMs) > 4000) {
                Serial.println("[Main] Hands-free abort — no speech detected (false trigger)");
                audio_io::stopMic();
                vad::reset();
                vad::init();  // Restore default VAD config
                appState.botState = BotState::IDLE;
                syncFaceToState();
                ws_client::sendEvent("audio:end");
                pendingSttFailAudio = true;  // played by main loop (Core 1) to avoid I2S contention
                continue;
            }
        }

        if (vadResult == vad::Result::END_OF_SPEECH && appState.wsConnected) {
            appState.botState = BotState::THINKING;
            syncFaceToState();
            ws_client::sendEvent("audio:end");
            audio_io::stopMic();
            vad::reset();
            // Restore default VAD config if we were in hands-free mode
            if (appState.listenTrigger != ListenTrigger::TOUCH) {
                vad::init();
            }
            Serial.printf("[Main] VAD: end-of-speech, stopping (trigger=%s)\n",
                appState.listenTrigger == ListenTrigger::TOUCH ? "touch" :
                appState.listenTrigger == ListenTrigger::WAKE_WORD ? "wake_word" : "gesture");
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

        // Yield 1ms after every frame so IDLE0 can run. Without this, the task
        // drains the I2S DMA backlog (which builds up during wake-word listening)
        // with rapid non-blocking reads, starving IDLE0 and triggering the WDT.
        vTaskDelay(pdMS_TO_TICKS(1));
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

    // pcmBuffer must be in internal SRAM (not PSRAM). libopus's Xtensa xcorr DSP
    // code reads from this buffer with tight inner loops; PSRAM cache-line latency
    // causes occasional alloca alignment faults inside pitch_search. Internal SRAM
    // is cache-coherent with the CPU and eliminates this class of issue entirely.
    // 1280 bytes is well within the ~72KB of free internal heap at boot.
    pcmBuffer = (int16_t*)heap_caps_malloc(OPUS_FRAME_SAMPLES * 2 * sizeof(int16_t), MALLOC_CAP_8BIT | MALLOC_CAP_INTERNAL);
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
        wifi_manager::init();
        Serial.println("[Main] WiFi started early (background connect)");
    }

    // ── 3. Display init + splash ───────────────────────────
    display::init();
    display::setFaceStyle(nvs_store::getFaceStyle());  // restore face style from NVS
    {
        // Restore idle display mode from NVS
        char idleMode[16];
        nvs_store::getIdleDisplayMode(idleMode, sizeof(idleMode));
        display::Mode idleDm = display::Mode::FACE;
        if (strcmp(idleMode, "clock") == 0)       idleDm = display::Mode::CLOCK;
        else if (strcmp(idleMode, "status") == 0) idleDm = display::Mode::STATUS;
        display::setHomeMode(idleDm);  // sets g_homeMode so wake() and dismissals respect it
    }
    display::setTranscriptOverlay(nvs_store::getDisplayTranscript());  // restore transcript pref
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

    // Presence detection is now driven by the mobile app (reverse BLE scan).
    // The app scans for this device's BLE advertisement and reports arrivals/
    // departures via the backend REST API. The backend then sends
    // presence:arrived / presence:departed events HERE via WebSocket.
    // No local RSSI scanning is needed on the firmware side.

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
    // forceProvision is set by the device:provision WS event (remote re-setup trigger).
    bool forceProvision = nvs_store::getForceProvision();
    if (forceProvision) {
        nvs_store::setForceProvision(false);  // One-shot: clear immediately so a crash loop can't lock the device
        Serial.println("[Main] Force-provision flag set — entering setup mode");
    }
    bool needsProvisioning = enterSetupFromBios || forceProvision || (!hasNvsCreds && !hasCompileCreds);
    bool provisionedViaBle = false;

    if (needsProvisioning) {
        // Start BLE for provisioning — Flutter app scans for 0xFFE0 service.
        // WiFi AP is NOT started here because BLE + WiFi crash on ESP32-S3.
        // Users provision via the Aksabot app (BLE) exclusively.
        ble_manager::init();
        Serial.println("[Main] BLE started — waiting for provisioning via app");

        boot_screen::showProvisioningPrompt(nullptr);  // BLE only, no AP name

        // Poll until credentials arrive via BLE
        bool shownConnected = false;
        while (!ble_manager::isProvisioned()) {
            // Update display when phone connects via BLE
            if (!shownConnected && ble_manager::isClientConnected()) {
                shownConnected = true;
                boot_screen::showProvisioningConnected();
                Serial.println("[Main] BLE client connected — showing setup screen");
            }
            // Reset if phone disconnects before finishing
            if (shownConnected && !ble_manager::isClientConnected()) {
                shownConnected = false;
                boot_screen::showProvisioningPrompt(nullptr);
                Serial.println("[Main] BLE client disconnected — back to waiting");
            }
            boot_screen::tickProvisioningAnimation(millis());
            delay(100);
        }

        provisionedViaBle = true;
        boot_screen::showProvisioningStatus("Credentials received!");
        Serial.println("[Main] Provisioned via BLE");
        delay(800);

        // ── First-boot: WiFi connect on boot screen (before face UI) ──
        // Keep BLE alive so the wifiStatusWatchTask can notify the app
        // of WiFi connection status. The face UI hasn't started yet, so
        // the boot screen is still visible.
        char ssidBuf[64] = {};
        const char* ssidDisplay = WIFI_SSID;
        if (nvs_store::getWifiSsid(ssidBuf, sizeof(ssidBuf)) && strlen(ssidBuf) > 0) {
            ssidDisplay = ssidBuf;
        }
        boot_screen::showConnecting(ssidDisplay);

        // Stop BLE completely before starting WiFi.
        // On this ESP32-S3 board, BLE + WiFi radio coexistence is unreliable —
        // WiFi drops if BLE is still active. Deiniting NimBLE releases the
        // BLE controller and frees radio resources for a stable WiFi connection.
        // ble_manager::deinit() also resets bleInitialized so startPresenceAdvertising()
        // can re-init cleanly after WiFi is up (section 13).
        ble_manager::deinit();
        delay(300);  // let radio settle

        wifi_manager::init();
        Serial.println("[Main] Waiting for Wi-Fi...");
        wifi_manager::waitForConnection(15000);

        if (wifi_manager::isConnected()) {
            boot_screen::showConnected(WiFi.localIP().toString().c_str());
            nvs_store::markSetupComplete();

            if (MDNS.begin("aksabot")) {
                MDNS.addService("aksabot", "tcp", 80);
            }
            device_server::start(FIRMWARE_VERSION);

            // Token + backend URL were already written via BLE before WiFi started.
            // No need to wait for HTTP delivery — just show success.
            boot_screen::showSetupComplete(ssidDisplay);
        } else {
            Serial.println("[Main] WiFi failed after provisioning");
            boot_screen::showConnectionFailed("Check credentials and restart.");
            delay(3000);
        }
    } else if (hasNvsCreds) {
        Serial.println("[Main] Using NVS WiFi credentials");
    } else {
        Serial.println("[Main] Using compile-time WiFi credentials");
    }

    // ── 10. Start face UI ───────────────────────────────────
    if (provisionedViaBle && appState.wifiConnected) {
        appState.botState = BotState::IDLE;
    } else if (isConfigured) {
        appState.botState = BotState::IDLE;
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

    // ── 11. WiFi connect (for already-configured devices) ───
    // After BLE provisioning, WiFi is already connected above.
    // This branch handles normal boot with existing credentials.
    if (!provisionedViaBle) {
        if (!isConfigured) {
            wifi_manager::init();
        }

        Serial.println("[Main] Waiting for Wi-Fi...");
        wifi_manager::waitForConnection(15000);

        if (wifi_manager::isConnected()) {
            Serial.println("[Main] WiFi connected");
            appState.wifiConnected = true;
            appState.botState = BotState::IDLE;
            syncFaceToState();
            updateStatusBar();
            resilience_audio::playClip(resilience_audio::Clip::BOOT);

            if (MDNS.begin("aksabot")) {
                MDNS.addService("aksabot", "tcp", 80);
            }

            if (firstBoot) {
                nvs_store::markSetupComplete();
            }
            bool hasToken2 = nvs_store::hasDeviceToken() || (strlen(DEVICE_TOKEN) > 0);
            if (!hasToken2) {
                device_server::setSetupMode(true);
            }
            device_server::start(FIRMWARE_VERSION);
        } else {
            Serial.println("[Main] WiFi failed — offline mode");
            appState.botState = BotState::OFFLINE;
            syncFaceToState();
            updateStatusBar();

            display::ReminderData rd = {};
            strncpy(rd.text, "Can't connect to WiFi. Check your network and restart.", sizeof(rd.text) - 1);
            rd.durationMs = 10000;
            strncpy(rd.icon, "error", sizeof(rd.icon) - 1);
            display::showReminder(rd);
        }
    }

    // ── 12. WebSocket connect ──────────────────────────────
    bool hasToken = nvs_store::hasDeviceToken() || (strlen(DEVICE_TOKEN) > 0);
    if (wifi_manager::isConnected() && hasToken) {
        Serial.println("[Main] Device token found — connecting to backend");
        ws_client::connect();
    } else if (wifi_manager::isConnected() && !hasToken) {
        Serial.println("[Main] No device token — waiting for app to complete setup");
        face::setExpression(face::Expression::THINKING, 200);
    }

    // ── 13. BLE presence advertising (deferred to WS connect) ──
    // Presence detection is app-driven: the phone scans for "Aksabot" by name.
    // BLE advertising is started AFTER the WebSocket connects (in the WS-connected
    // handler below) to avoid NimBLE init disrupting the WS TCP handshake.
    // Restore last known presence state from NVS so the display dot is correct
    // immediately on boot, before the first WS event arrives.
    if (nvs_store::getPresenceEnabled() && nvs_store::getPresencePresent()) {
        appState.presenceState = PresenceState::PRESENT;
    }
    updateStatusBar();
    Serial.printf("[Main] Presence detection: %s (app-driven), last state: %s\n",
        nvs_store::getPresenceEnabled() ? "enabled" : "disabled",
        nvs_store::getPresencePresent() ? "present" : "away");

    // ── 14. Wake word detection ─────────────────────────────
#if HANDS_FREE_ENABLED
    wake_word::init();
    wake_word::onWake([]() {
        startHandsFreeRecording(ListenTrigger::WAKE_WORD);
    });
    wake_word::startListening();
    Serial.println("[Main] Wake word detection active");
#else
    Serial.println("[Main] Wake word detection disabled (PTT only)");
#endif

    // ── 15. Gesture sensor (APDS-9960) ────────────────────
    if (gesture::init()) {
        gesture::onGesture([](gesture::Type g) {
            power_manager::recordInteraction();
            switch (g) {
                case gesture::Type::WAVE:
#if HANDS_FREE_ENABLED
                    // Wave to start hands-free recording
                    startHandsFreeRecording(ListenTrigger::GESTURE);
#else
                    Serial.println("[Gesture] Wave ignored — hands-free disabled");
#endif
                    break;
                case gesture::Type::SWIPE_UP:
                    // Volume up
                    audio_io::setVolume(constrain(nvs_store::getVolume() + 10, 0, 100));
                    nvs_store::setVolume(constrain(nvs_store::getVolume() + 10, 0, 100));
                    Serial.println("[Gesture] Volume up");
                    break;
                case gesture::Type::SWIPE_DOWN:
                    // Volume down
                    audio_io::setVolume(constrain(nvs_store::getVolume() - 10, 0, 100));
                    nvs_store::setVolume(constrain(nvs_store::getVolume() - 10, 0, 100));
                    Serial.println("[Gesture] Volume down");
                    break;
                case gesture::Type::SWIPE_LEFT:
                case gesture::Type::SWIPE_RIGHT:
                    // Dismiss current display/reminder
                    if (display::getMode() == display::Mode::REMINDER) {
                        display::setMode(display::getHomeMode());
                        ws_client::sendEvent("proactive:dismiss");
                    }
                    break;
                default:
                    break;
            }
        });

        gesture::onProximity([](bool near) {
            if (near) {
                power_manager::recordInteraction();  // Wake display when someone approaches
                Serial.println("[Gesture] Proximity: near");
            }
        });

        Serial.println("[Main] Gesture sensor active");
    } else {
        Serial.println("[Main] Gesture sensor not found — skipping");
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

    // Safety: auto-revert from THINKING/LISTENING/SPEAKING if stuck
    // THINKING/LISTENING: 15s timeout (backend should respond faster)
    // SPEAKING: 30s timeout (long responses can take a while, but not forever)
    static uint32_t stuckCheckMs = 0;
    if (appState.botState == BotState::THINKING || appState.botState == BotState::LISTENING) {
        if (stuckCheckMs == 0) {
            stuckCheckMs = now;
        } else if ((now - stuckCheckMs) > 15000) {
            Serial.printf("[Main] Stuck state timeout (thinking/listening) — reverting to IDLE (wsConnected=%d, heap=%u)\n",
                          (int)appState.wsConnected, ESP.getFreeHeap());
            appState.botState = BotState::IDLE;
            syncFaceToState();
            display::setTranscriptText("");
            stuckCheckMs = 0;
        }
    } else if (appState.botState == BotState::SPEAKING) {
        if (stuckCheckMs == 0) {
            stuckCheckMs = now;
        } else if ((now - stuckCheckMs) > 30000) {
            Serial.println("[Main] Stuck state timeout (speaking) — force idle");
            playbackActive      = false;
            playbackDone        = false;
            playbackBuffering   = true;
            pendingResponseEnds = 0;
            xQueueReset(playbackQueue);
            face::feedAudioAmplitude(0);
            appState.botState = BotState::IDLE;
            syncFaceToState();
            display::setTranscriptText("");
            stuckCheckMs = 0;
        }
    } else {
        stuckCheckMs = 0;
    }

    // Safety: if WS disconnects mid-speech, abort playback immediately
    // (don't wait for the 30s timeout — connection is already gone)
    static bool prevWsForPlayback = false;
    if (prevWsForPlayback && !appState.wsConnected) {
        if (appState.botState == BotState::SPEAKING || appState.botState == BotState::THINKING) {
            Serial.println("[Main] WS disconnected mid-response — aborting playback");
            playbackActive      = false;
            playbackDone        = false;
            playbackBuffering   = true;
            pendingResponseEnds = 0;
            xQueueReset(playbackQueue);
            face::feedAudioAmplitude(0);
            display::setTranscriptText("");
            // Don't set IDLE here — the connectivity check below will set OFFLINE
        }
    }
    prevWsForPlayback = appState.wsConnected;

    // ── Idle glance (show time/weather occasionally) ──
    static uint32_t nextGlanceMs = 0;
    if (nextGlanceMs == 0) nextGlanceMs = now + 180000 + (esp_random() % 120000);  // First: 3-5 min
    if (appState.botState == BotState::IDLE &&
        display::getMode() == display::Mode::FACE &&
        (power_manager::getState() == power_manager::PowerState::ACTIVE ||
         power_manager::getState() == power_manager::PowerState::DIM) &&
        display::hasContextData() &&
        now >= nextGlanceMs) {
        power_manager::recordInteraction();  // Wake from DIM → ACTIVE
        display::showGlance();
        nextGlanceMs = now + 180000 + (esp_random() % 120000);  // Next: 3-5 min
    }
    // Reset glance timer on user interaction (avoid glance right after talking)
    if (appState.botState != BotState::IDLE) {
        nextGlanceMs = now + 180000 + (esp_random() % 120000);
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
        display::setMode(display::getHomeMode());
    }

    // Presence is now app-driven — no local tick needed.

    // Tick gesture sensor (APDS-9960)
    gesture::tick(now);

    // Tick power management and status LED
    {
        auto prevPower = power_manager::getState();
        power_manager::tick(now);
        if (prevPower != power_manager::PowerState::SLEEPING &&
            power_manager::getState() == power_manager::PowerState::SLEEPING) {
            resilience_audio::playClip(resilience_audio::Clip::SLEEP);
        }
    }
    status_led::tick(now);

    // Explicit WiFi reconnect with backoff — fallback for when setAutoReconnect
    // silently stops retrying (router restart, driver exhaustion, etc.)
    wifi_manager::tick();

    // Sync connectivity state — check actual WiFi, not just our flag
    bool wifiNow = wifi_manager::isConnected();
    if (wifiNow && !appState.wifiConnected) {
        appState.wifiConnected = true;
        bool hasToken = nvs_store::hasDeviceToken() || (strlen(DEVICE_TOKEN) > 0);
        if (hasToken && !appState.wsConnected) {
            ws_client::connect();
            Serial.println("[Main] WiFi recovered — connecting WS");
        }
        ui_audio::play(ui_audio::Clip::WIFI_CONNECTED);  // WiFi reconnect (not first boot — BOOT covers that)
    } else if (!wifiNow && appState.wifiConnected) {
        appState.wifiConnected = false;
    }

    BotState prevState = appState.botState;
    if (!appState.wifiConnected && appState.botState != BotState::OFFLINE &&
        appState.botState != BotState::LISTENING) {
        // WiFi gone — go OFFLINE. SPEAKING/THINKING playback was already
        // cleaned up by the WS disconnect handler above.
        appState.botState = BotState::OFFLINE;
    } else if (appState.wifiConnected && appState.botState == BotState::OFFLINE) {
        appState.botState = BotState::IDLE;
    }

    if (appState.botState != prevState) {
        syncFaceToState();
    }

    // Refresh status bar during active states (for stall indicator blinking)
    if (appState.botState == BotState::SPEAKING || appState.botState == BotState::THINKING) {
        updateStatusBar();
    }

    // Throttle status bar updates — only refresh when connectivity actually changes
    static bool prevWifi = false;
    static bool prevWs = false;
    if (appState.wifiConnected != prevWifi || appState.wsConnected != prevWs) {

        // ── Face + audio reactions to connectivity changes (only when idle) ──
        if (appState.botState == BotState::IDLE || appState.botState == BotState::OFFLINE) {
            if (!appState.wifiConnected && prevWifi) {
                // WiFi lost → offline clip + sad face
                resilience_audio::playClip(resilience_audio::Clip::OFFLINE);
                face::setExpression(face::Expression::SAD, 300);
                scheduleFaceRevert(3000);
            } else if (appState.wifiConnected && !appState.wsConnected && prevWs) {
                // WS dropped but WiFi still up → disconnected clip + confused face
                ui_audio::play(ui_audio::Clip::SERVER_DISCONNECTED);
                face::setExpression(face::Expression::CONFUSED, 200);
                scheduleFaceRevert(3000);
            } else if (appState.wifiConnected && !appState.wsConnected && !prevWifi) {
                // WiFi just recovered but WS not yet → confused (connecting...)
                face::setExpression(face::Expression::CONFUSED, 200);
                scheduleFaceRevert(3000);
            }
        }

        // WS just connected — server connected clip + happy face + send device info
        if (appState.wsConnected && !prevWs) {
            ui_audio::play(ui_audio::Clip::SERVER_CONNECTED);
            // Start BLE advertising here (after WS is confirmed connected) so the
            // phone can scan for "Aksabot". Deferred from setup() to avoid NimBLE
            // init disrupting the WS TCP handshake.
            if (nvs_store::getPresenceEnabled()) {
                ble_manager::startPresenceAdvertising();
            }

            static bool wasEverConnected = false;  // Distinguish boot vs reconnect

            appState.botState = BotState::IDLE;
            face::setExpression(face::Expression::HAPPY, 200);
            scheduleFaceRevert(2000);

            // Report device diagnostics to backend on every connect.
            // Backend logs these for device health monitoring.
            char infoPayload[256];
            snprintf(infoPayload, sizeof(infoPayload),
                "{"
                "\"firmwareVersion\":\"%s\","
                "\"wifiSsid\":\"%s\","
                "\"wifiRssi\":%d,"
                "\"ip\":\"%s\","
                "\"uptimeSec\":%lu,"
                "\"freeHeap\":%lu,"
                "\"sdMounted\":%s"
                "}",
                FIRMWARE_VERSION,
                WiFi.SSID().c_str(),
                WiFi.RSSI(),
                WiFi.localIP().toString().c_str(),
                millis() / 1000,
                (unsigned long)ESP.getFreeHeap(),
                sd_storage::isMounted() ? "true" : "false"
            );
            ws_client::sendEvent("device:info", infoPayload);

            // Tell backend this was a reconnect (not first boot)
            // so it can roast the bad connection instead of a normal greeting
            if (wasEverConnected) {
                ws_client::sendEvent("reconnect:back");
            }
            wasEverConnected = true;
        }
        prevWifi = appState.wifiConnected;
        prevWs = appState.wsConnected;
        updateStatusBar();
        status_led::syncToState();
    }

#if HANDS_FREE_ENABLED
    // Auto-resume wake word listening when IDLE and connected.
    // Delay 2s after going IDLE to avoid echo (hearing bot's own speech).
    static uint32_t idleSinceMs = 0;
    if (appState.botState == BotState::IDLE && appState.wsConnected) {
        if (idleSinceMs == 0) idleSinceMs = now;
        if (!wake_word::isListening() && (now - idleSinceMs) > 2000) {
            wake_word::startListening();
        }
    } else {
        idleSinceMs = 0;
    }
#endif

    // Consume STT fail clip request from audio task (Core 0)
    if (pendingSttFailAudio) {
        pendingSttFailAudio = false;
        resilience_audio::playClip(resilience_audio::Clip::STT_FAIL);
    }

    vTaskDelay(pdMS_TO_TICKS(10));
}
