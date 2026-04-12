#include "wake_word.h"
#include "config.h"
#include "state.h"
#include "audio_io.h"
#include "vad.h"
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

namespace wake_word {

// ── Configuration ────────────────────────────────────────────

// How long to buffer audio for potential wake word (frames of 20ms)
static constexpr int DETECT_WINDOW_FRAMES = 100;  // 2 seconds at 16kHz/320 samples
// Minimum speech frames to consider as potential wake word
static constexpr int MIN_SPEECH_FRAMES = 10;       // ~200ms
// Maximum speech frames (wake word should be short)
static constexpr int MAX_SPEECH_FRAMES = 60;        // ~1.2s
// Cooldown after detection to prevent rapid re-triggers
static constexpr uint32_t COOLDOWN_MS = 3000;

// Energy threshold for speech detection in wake word mode
// Lower than VAD default because we want to catch quiet "Hey Aksa"
static constexpr float WAKE_ENERGY_THRESHOLD = 0.015f;

// ── State ────────────────────────────────────────────────────

static bool initialized = false;
static volatile bool listening = false;
static WakeCallback wakeCb = nullptr;
static TaskHandle_t wakeTask = nullptr;
static float sensitivity = 0.5f;
static uint32_t lastDetectionMs = 0;

// ── Background PCM buffer (in PSRAM) ─────────────────────────

static int16_t* pcmBuffer = nullptr;  // One frame buffer

// ── VAD state for wake word detection ────────────────────────

static int consecutiveSpeechFrames = 0;
static int consecutiveSilenceFrames = 0;
static bool speechActive = false;
static float noiseFloor = 0.0f;
static constexpr float NOISE_ADAPT_RATE = 0.005f;

static float computeRMS(const int16_t* pcm, size_t count) {
    float sum = 0;
    for (size_t i = 0; i < count; i++) {
        float s = pcm[i] / 32768.0f;
        sum += s * s;
    }
    return sqrtf(sum / count);
}

// ── Wake word detection task ─────────────────────────────────

static void wakeWordTask(void* param) {
    Serial.println("[WakeWord] Detection task started on Core 0");

    // Initial noise floor calibration (~500ms of silence)
    float calSum = 0;
    int calCount = 0;
    for (int i = 0; i < 25; i++) {
        size_t read = audio_io::readMic(pcmBuffer, OPUS_FRAME_SAMPLES);
        if (read > 0) {
            calSum += computeRMS(pcmBuffer, read);
            calCount++;
        }
        vTaskDelay(pdMS_TO_TICKS(1));
    }
    if (calCount > 0) {
        noiseFloor = calSum / calCount;
        Serial.printf("[WakeWord] Noise floor calibrated: %.4f\n", noiseFloor);
    }

    for (;;) {
        // Wait if not listening
        while (!listening) {
            vTaskDelay(pdMS_TO_TICKS(100));
            if (!initialized) return;
        }

        // Only listen when bot is IDLE
        if (appState.botState != BotState::IDLE) {
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }

        // Read one frame from mic
        size_t samplesRead = audio_io::readMic(pcmBuffer, OPUS_FRAME_SAMPLES);
        if (samplesRead == 0) {
            vTaskDelay(pdMS_TO_TICKS(1));
            continue;
        }

        float rms = computeRMS(pcmBuffer, samplesRead);

        // Adaptive noise floor
        if (!speechActive) {
            noiseFloor = noiseFloor * (1.0f - NOISE_ADAPT_RATE) + rms * NOISE_ADAPT_RATE;
        }

        // Dynamic threshold based on noise floor and sensitivity
        // Lower sensitivity = higher threshold = fewer false positives
        float threshold = noiseFloor + WAKE_ENERGY_THRESHOLD * (1.5f - sensitivity);

        if (rms > threshold) {
            consecutiveSpeechFrames++;
            consecutiveSilenceFrames = 0;

            if (!speechActive && consecutiveSpeechFrames >= 3) {
                speechActive = true;
                Serial.printf("[WakeWord] Speech onset detected (RMS=%.4f, floor=%.4f)\n",
                              rms, noiseFloor);
            }
        } else {
            consecutiveSilenceFrames++;

            if (speechActive) {
                // Check if speech segment is complete (silence after speech)
                if (consecutiveSilenceFrames >= 15) {  // 300ms silence = end of utterance
                    uint32_t now = millis();

                    // Check if speech duration was in wake word range
                    if (consecutiveSpeechFrames >= MIN_SPEECH_FRAMES &&
                        consecutiveSpeechFrames <= MAX_SPEECH_FRAMES &&
                        (now - lastDetectionMs) > COOLDOWN_MS) {

                        // Potential wake word detected!
                        // In a full implementation, this would send the audio buffer
                        // to the backend for verification. For now, we trigger on
                        // any short speech segment while idle.
                        //
                        // TODO: When ESP-SR is integrated, replace this with
                        // proper keyword model inference. The task structure and
                        // callback mechanism stay the same.
                        lastDetectionMs = now;
                        Serial.printf("[WakeWord] Wake detected! (%d speech frames, %.4f RMS)\n",
                                      consecutiveSpeechFrames, rms);

                        if (wakeCb) {
                            wakeCb();
                        }
                    }

                    // Reset
                    speechActive = false;
                    consecutiveSpeechFrames = 0;
                    consecutiveSilenceFrames = 0;
                }
            } else {
                consecutiveSpeechFrames = 0;
            }
        }

        vTaskDelay(pdMS_TO_TICKS(1));
    }
}

// ── Public API ───────────────────────────────────────────────

void init() {
    if (initialized) return;

    // Allocate PCM buffer in PSRAM
    pcmBuffer = (int16_t*)ps_malloc(OPUS_FRAME_SAMPLES * sizeof(int16_t));
    if (!pcmBuffer) {
        Serial.println("[WakeWord] Failed to allocate PCM buffer in PSRAM");
        return;
    }

    initialized = true;
    Serial.printf("[WakeWord] Initialized (PSRAM free: %u)\n", ESP.getFreePsram());
}

void onWake(WakeCallback cb) {
    wakeCb = cb;
}

void startListening() {
    if (!initialized) return;
    if (listening) return;

    listening = true;

    // Reset detection state
    consecutiveSpeechFrames = 0;
    consecutiveSilenceFrames = 0;
    speechActive = false;

    // Create task if not already running
    if (!wakeTask) {
        xTaskCreatePinnedToCore(
            wakeWordTask,
            "wake_word",
            4096,         // 4KB stack (lightweight — just reads mic + computes RMS)
            nullptr,
            4,            // Priority 4 (between ws 3 and audio 5)
            &wakeTask,
            0             // Core 0 (same as audio capture)
        );
    }

    Serial.println("[WakeWord] Listening started");
}

void stopListening() {
    if (!listening) return;
    listening = false;
    speechActive = false;
    consecutiveSpeechFrames = 0;
    consecutiveSilenceFrames = 0;
    Serial.println("[WakeWord] Listening paused");
}

bool isListening() {
    return listening;
}

void setSensitivity(float s) {
    sensitivity = constrain(s, 0.0f, 1.0f);
    Serial.printf("[WakeWord] Sensitivity set to %.2f\n", sensitivity);
}

}  // namespace wake_word
