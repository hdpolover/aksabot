#include "wake_word.h"
#include "config.h"
#include "state.h"
#include <Arduino.h>

namespace wake_word {

// ── Configuration ────────────────────────────────────────────

// Minimum speech frames to consider as potential wake word (~200ms)
static constexpr int MIN_SPEECH_FRAMES = 10;
// Maximum speech frames (wake word should be short, ~1.2s)
static constexpr int MAX_SPEECH_FRAMES = 60;
// Cooldown after detection to prevent rapid re-triggers
static constexpr uint32_t COOLDOWN_MS = 3000;
// Energy threshold for speech detection in wake word mode
static constexpr float WAKE_ENERGY_THRESHOLD = 0.0004f;

// ── State ────────────────────────────────────────────────────

static bool initialized = false;
static volatile bool listening = false;
static WakeCallback wakeCb = nullptr;
static float sensitivity = 0.5f;
static uint32_t lastDetectionMs = 0;

// Speech tracking
static int consecutiveSpeechFrames = 0;
static int consecutiveSilenceFrames = 0;
static bool speechActive = false;
static float noiseFloor = 0.0f;
static constexpr float NOISE_ADAPT_RATE = 0.005f;
static int calibrationFrames = 0;
static constexpr int CAL_FRAMES_NEEDED = 25;  // ~500ms of silence for calibration

// ── Public API ───────────────────────────────────────────────

void init() {
    if (initialized) return;
    initialized = true;
    Serial.println("[WakeWord] Initialized (piggyback mode — shares audio capture loop)");
}

void onWake(WakeCallback cb) {
    wakeCb = cb;
}

void startListening() {
    if (!initialized) return;
    if (listening) return;
    listening = true;
    consecutiveSpeechFrames = 0;
    consecutiveSilenceFrames = 0;
    speechActive = false;
    // Reset calibration so noise floor adapts to current environment
    calibrationFrames = 0;
    noiseFloor = 0.0f;
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

/// Called from audioCaptureLoop with each PCM frame when bot is IDLE.
/// This avoids a separate FreeRTOS task and I2S contention.
///
/// NOT in the header — declared as a friend function called from main.cpp's
/// audio capture loop. The audio loop already reads mic frames continuously;
/// when IDLE, it feeds them here instead of encoding/sending.
///
/// Returns true if wake word was detected (caller should start recording).
static float computeRMS(const int16_t* pcm, size_t count) {
    float sum = 0;
    for (size_t i = 0; i < count; i++) {
        float s = pcm[i] / 32768.0f;
        sum += s * s;
    }
    return sqrtf(sum / count);
}

}  // namespace wake_word

// ── Extern function called from audioCaptureLoop ─────────────
// This is outside the namespace so main.cpp can call it directly.

bool wake_word_processMicFrame(const int16_t* pcm, size_t sampleCount) {
    using namespace wake_word;

    if (!initialized || !listening) return false;

    float rms = computeRMS(pcm, sampleCount);

    // Calibration phase — learn noise floor from initial silence
    if (calibrationFrames < CAL_FRAMES_NEEDED) {
        noiseFloor = (calibrationFrames == 0) ? rms :
            noiseFloor * (1.0f - 0.1f) + rms * 0.1f;  // Fast adapt during calibration
        calibrationFrames++;
        if (calibrationFrames == CAL_FRAMES_NEEDED) {
            Serial.printf("[WakeWord] Noise floor calibrated: %.4f\n", noiseFloor);
        }
        return false;
    }

    // Adaptive noise floor (slow adapt during normal operation)
    if (!speechActive) {
        noiseFloor = noiseFloor * (1.0f - NOISE_ADAPT_RATE) + rms * NOISE_ADAPT_RATE;
    }

    // Dynamic threshold based on noise floor and sensitivity
    float threshold = noiseFloor + WAKE_ENERGY_THRESHOLD * (1.5f - sensitivity);

    // Debug: log every ~2 seconds so we can see levels
    static int debugCounter = 0;
    debugCounter++;
    if (debugCounter % 100 == 0) {
        Serial.printf("[WakeWord] RMS=%.4f floor=%.4f thresh=%.4f speech=%d frames=%d\n",
                      rms, noiseFloor, threshold, speechActive ? 1 : 0, consecutiveSpeechFrames);
    }

    if (rms > threshold) {
        consecutiveSpeechFrames++;
        consecutiveSilenceFrames = 0;

        if (!speechActive && consecutiveSpeechFrames >= 3) {
            speechActive = true;
        }
    } else {
        consecutiveSilenceFrames++;

        if (speechActive) {
            // Speech segment ended (300ms silence)
            if (consecutiveSilenceFrames >= 15) {
                uint32_t now = millis();

                // Check if speech duration matches wake word length
                if (consecutiveSpeechFrames >= MIN_SPEECH_FRAMES &&
                    consecutiveSpeechFrames <= MAX_SPEECH_FRAMES &&
                    (now - lastDetectionMs) > COOLDOWN_MS) {

                    lastDetectionMs = now;
                    Serial.printf("[WakeWord] Wake detected! (%d frames, RMS=%.4f)\n",
                                  consecutiveSpeechFrames, rms);

                    // Reset state
                    speechActive = false;
                    consecutiveSpeechFrames = 0;
                    consecutiveSilenceFrames = 0;

                    if (wakeCb) {
                        wakeCb();
                        return true;
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

    return false;
}
