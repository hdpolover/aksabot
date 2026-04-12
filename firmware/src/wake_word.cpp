#include "wake_word.h"
#include <Arduino.h>

namespace wake_word {

// ── Configuration ────────────────────────────────────────────

// Voice must be at least this many times louder than the adaptive noise floor
// to count as speech.  Multiplicative scaling means the threshold rises with
// ambient noise automatically, so room hum / AC / keyboard can't fake speech.
//   2.5× is the default.  Raise toward 3.5 if ambient noise triggers false
//   positives.  Lower toward 1.8 if you're in a quiet room and still miss.
static constexpr float    WAKE_SPEECH_RATIO = 2.5f;

// Absolute floor — prevents the threshold from becoming too low in a perfectly
// silent room (where noiseFloor × ratio might be tiny).
static constexpr float    WAKE_MIN_THRESHOLD = 0.003f;

// Wake word duration window. "Hey Aksa" sits around 600–800ms = 30–40 frames.
// Kept wide (20–60) to handle faster/slower speech.
static constexpr int      MIN_SPEECH_FRAMES = 20;   // ~400ms
static constexpr int      MAX_SPEECH_FRAMES = 60;   // ~1.2s

// Silence frames needed after speech to end a segment (~300ms).
static constexpr int      SILENCE_END_FRAMES = 15;

// Minimum silence frames to reset a short burst before speech starts.
static constexpr int      SILENCE_RESET_FRAMES = 5;

// Cooldown after detection to prevent double-trigger.
static constexpr uint32_t COOLDOWN_MS = 3000;

// ── State ────────────────────────────────────────────────────

static bool              initialized              = false;
static volatile bool     listening                = false;
static WakeCallback      wakeCb                   = nullptr;
static float             sensitivity              = 0.5f;
static volatile uint32_t lastDetectionMs          = 0;

static int               consecutiveSpeechFrames  = 0;
static int               consecutiveSilenceFrames = 0;
static bool              speechActive             = false;
static float             noiseFloor               = 0.0f;
static int               calibrationFrames        = 0;

static constexpr float   NOISE_ADAPT_RATE  = 0.005f;
static constexpr int     CAL_FRAMES_NEEDED = 25;   // ~500ms initial calibration

// ── Helpers ──────────────────────────────────────────────────

static float computeRMS(const int16_t* pcm, size_t count) {
    float sum = 0;
    for (size_t i = 0; i < count; i++) {
        float s = pcm[i] / 32768.0f;
        sum += s * s;
    }
    return sqrtf(sum / count);
}

// ── Public API ───────────────────────────────────────────────

void init() {
    if (initialized) return;
    initialized = true;
    Serial.println("[WakeWord] Initialized (energy-based, piggyback mode)");
}

void onWake(WakeCallback cb) { wakeCb = cb; }
bool isListening()           { return listening; }

void startListening() {
    if (!initialized || listening) return;
    consecutiveSpeechFrames  = 0;
    consecutiveSilenceFrames = 0;
    speechActive      = false;
    calibrationFrames = 0;
    noiseFloor        = 0.0f;
    listening = true;
    Serial.println("[WakeWord] Listening started");
}

void stopListening() {
    if (!listening) return;
    listening    = false;
    speechActive = false;
    consecutiveSpeechFrames  = 0;
    consecutiveSilenceFrames = 0;
    Serial.println("[WakeWord] Listening paused");
}

void setSensitivity(float s) {
    sensitivity = s < 0.0f ? 0.0f : (s > 1.0f ? 1.0f : s);
    Serial.printf("[WakeWord] Sensitivity %.2f\n", sensitivity);
}

}  // namespace wake_word

// ── Extern: called from audioCaptureLoop ─────────────────────

bool wake_word_processMicFrame(const int16_t* pcm, size_t sampleCount) {
    using namespace wake_word;
    if (!initialized || !listening) return false;

    float rms = computeRMS(pcm, sampleCount);

    // Calibration — learn ambient noise floor from initial silence
    if (calibrationFrames < CAL_FRAMES_NEEDED) {
        noiseFloor = (calibrationFrames == 0) ? rms
                   : noiseFloor * 0.9f + rms * 0.1f;
        calibrationFrames++;
        if (calibrationFrames == CAL_FRAMES_NEEDED) {
            Serial.printf("[WakeWord] Noise floor calibrated: %.4f\n", noiseFloor);
        }
        return false;
    }

    // Slowly adapt noise floor during silence (not during active speech)
    if (!speechActive) {
        noiseFloor = noiseFloor * (1.0f - NOISE_ADAPT_RATE) + rms * NOISE_ADAPT_RATE;
    }

    // Multiplicative threshold: voice must be WAKE_SPEECH_RATIO × the noise floor.
    // Sensitivity shifts the ratio:
    //   sensitivity=0.5 → ratio = WAKE_SPEECH_RATIO × 1.0  (default)
    //   sensitivity=1.0 → ratio = WAKE_SPEECH_RATIO × 0.5  (more sensitive)
    //   sensitivity=0.0 → ratio = WAKE_SPEECH_RATIO × 1.5  (more strict)
    float ratio     = WAKE_SPEECH_RATIO * (1.5f - sensitivity);
    float threshold = noiseFloor * ratio;
    if (threshold < WAKE_MIN_THRESHOLD) threshold = WAKE_MIN_THRESHOLD;

    // Debug log every ~2s (100 frames × 20ms)
    static int debugCounter = 0;
    if (++debugCounter % 100 == 0) {
        Serial.printf("[WakeWord] RMS=%.4f floor=%.4f thresh=%.4f speech=%d frames=%d\n",
                      rms, noiseFloor, threshold,
                      speechActive ? 1 : 0, consecutiveSpeechFrames);
    }

    if (rms > threshold) {
        consecutiveSpeechFrames++;
        consecutiveSilenceFrames = 0;
        if (!speechActive && consecutiveSpeechFrames >= 3) {
            speechActive = true;
        }
    } else {
        consecutiveSilenceFrames++;
        if (!speechActive) {
            // Short burst below threshold — reset counter so noise spikes
            // don't accumulate toward the MIN_SPEECH_FRAMES window
            if (consecutiveSilenceFrames >= SILENCE_RESET_FRAMES) {
                consecutiveSpeechFrames = 0;
            }
        } else {
            // Active speech — check if segment ended
            if (consecutiveSilenceFrames >= SILENCE_END_FRAMES) {
                bool durationOk = (consecutiveSpeechFrames >= MIN_SPEECH_FRAMES &&
                                   consecutiveSpeechFrames <= MAX_SPEECH_FRAMES);
                uint32_t now    = millis();
                bool cooldownOk = (now - lastDetectionMs) > COOLDOWN_MS;

                Serial.printf("[WakeWord] Segment: %d frames  durationOk=%d cooldownOk=%d\n",
                              consecutiveSpeechFrames, durationOk, cooldownOk);

                if (durationOk && cooldownOk) {
                    lastDetectionMs          = now;
                    speechActive             = false;
                    consecutiveSpeechFrames  = 0;
                    consecutiveSilenceFrames = 0;
                    Serial.println("[WakeWord] Wake detected!");
                    if (wakeCb) {
                        wakeCb();
                        return true;
                    }
                }

                speechActive             = false;
                consecutiveSpeechFrames  = 0;
                consecutiveSilenceFrames = 0;
            }
        }
    }

    return false;
}
