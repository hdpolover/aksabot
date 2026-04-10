#include "vad.h"
#include <Arduino.h>
#include <cmath>

// ── Internal state ─────────────────────────────────────
static vad::Config cfg;

static float noiseFloor = 0.0f;
static float lastEnergy = 0.0f;
static uint16_t silenceFrameCount = 0;
static uint16_t speechFrameCount = 0;
static bool speechDetected = false;
static bool initialized = false;

// ── DSP helpers ────────────────────────────────────────

/// Compute RMS energy of a PCM frame, normalized to 0.0–1.0.
static float computeRms(const int16_t* pcm, size_t count) {
    if (count == 0) return 0.0f;

    int64_t sumSq = 0;
    for (size_t i = 0; i < count; i++) {
        int32_t sample = pcm[i];
        sumSq += sample * sample;
    }

    float rms = sqrtf((float)sumSq / count);
    return rms / 32768.0f;  // Normalize to 0.0–1.0
}

/// Compute zero-crossing rate (fraction of adjacent samples with sign change).
static float computeZcr(const int16_t* pcm, size_t count) {
    if (count < 2) return 0.0f;

    uint32_t crossings = 0;
    for (size_t i = 1; i < count; i++) {
        if ((pcm[i] >= 0) != (pcm[i - 1] >= 0)) {
            crossings++;
        }
    }

    return (float)crossings / (count - 1);
}

// ── Public API ─────────────────────────────────────────

void vad::init(const Config& config) {
    cfg = config;
    noiseFloor = cfg.energyThreshold * 0.5f;  // Start with conservative estimate
    lastEnergy = 0.0f;
    silenceFrameCount = 0;
    speechFrameCount = 0;
    speechDetected = false;
    initialized = true;

    Serial.printf("[VAD] Init — energy=%.3f, silence_frames=%u (%.1fs)\n",
        cfg.energyThreshold, cfg.silenceFramesForEnd,
        cfg.silenceFramesForEnd * 0.02f);
}

void vad::calibrate(const int16_t* pcm, size_t sampleCount) {
    if (!initialized) return;

    float rms = computeRms(pcm, sampleCount);

    // Use calibration samples to set noise floor
    // Blend with existing estimate for stability
    noiseFloor = noiseFloor * 0.7f + rms * 0.3f;

    // Set energy threshold above the measured noise floor
    // with some headroom to avoid false triggers
    float newThreshold = noiseFloor * 3.0f;
    if (newThreshold > cfg.energyThreshold) {
        cfg.energyThreshold = newThreshold;
    }

    Serial.printf("[VAD] Calibrated — noise_floor=%.4f, threshold=%.4f\n",
        noiseFloor, cfg.energyThreshold);
}

vad::Result vad::analyze(const int16_t* pcm, size_t sampleCount) {
    if (!initialized) return Result::SILENCE;

    float rms = computeRms(pcm, sampleCount);
    float zcr = computeZcr(pcm, sampleCount);
    lastEnergy = rms;

    // Adaptive noise floor — slowly track the ambient level
    if (rms < noiseFloor * 1.5f) {
        noiseFloor += (rms - noiseFloor) * cfg.adaptiveRate;
    }

    // Speech detection: energy above threshold AND ZCR in speech range
    bool isSpeech = false;

    if (rms > cfg.energyThreshold) {
        // High energy — likely speech or loud noise
        // Use ZCR to discriminate: very high ZCR = noise, moderate = speech
        if (zcr < cfg.zcrThresholdHigh) {
            isSpeech = true;
        }
    } else if (rms > noiseFloor * 2.0f && zcr > cfg.zcrThresholdLow && zcr < cfg.zcrThresholdHigh) {
        // Moderate energy with speech-like ZCR — could be quiet speech
        isSpeech = true;
    }

    if (isSpeech) {
        speechFrameCount++;
        silenceFrameCount = 0;

        if (speechFrameCount >= cfg.speechFramesForStart) {
            speechDetected = true;
        }

        return Result::SPEECH;
    } else {
        speechFrameCount = 0;

        // Only count silence after speech has been detected
        if (speechDetected) {
            silenceFrameCount++;

            if (silenceFrameCount >= cfg.silenceFramesForEnd) {
                return Result::END_OF_SPEECH;
            }
        }

        return Result::SILENCE;
    }
}

void vad::reset() {
    silenceFrameCount = 0;
    speechFrameCount = 0;
    speechDetected = false;
    lastEnergy = 0.0f;
    // Keep noise floor — it should persist across recordings
}

float vad::getNoiseFloor() {
    return noiseFloor;
}

float vad::getLastEnergy() {
    return lastEnergy;
}

bool vad::hasSpeechStarted() {
    return speechDetected;
}
