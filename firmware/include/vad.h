#pragma once
#include <cstdint>
#include <cstddef>

/// Voice Activity Detection (VAD) module.
///
/// Analyzes PCM audio frames to detect speech vs silence.
/// Used to auto-stop recording when the user finishes speaking,
/// replacing the manual touch-release requirement.
///
/// Algorithm:
///   1. Compute short-term energy (RMS) of each frame
///   2. Compute zero-crossing rate (ZCR) for voiced/unvoiced discrimination
///   3. Compare against adaptive threshold (calibrated from initial silence)
///   4. Track consecutive silent frames → trigger end-of-speech
///
/// Usage:
///   vad::init();
///   vad::calibrate(silenceFrames, count);  // optional: learn noise floor
///   while (recording) {
///       vad::Result r = vad::analyze(pcmFrame, frameSize);
///       if (r == vad::Result::END_OF_SPEECH) break;
///   }
namespace vad {

/// VAD analysis result for a single frame.
enum class Result : uint8_t {
    SPEECH,             // Active speech detected
    SILENCE,            // No speech (but not enough silence to end)
    END_OF_SPEECH,      // Silence exceeded threshold — stop recording
};

/// Configuration.
struct Config {
    float energyThreshold = 0.02f;      // RMS threshold (0.0–1.0 normalized)
    float zcrThresholdLow = 0.05f;      // ZCR below this = likely silence
    float zcrThresholdHigh = 0.35f;     // ZCR above this = likely unvoiced speech
    uint16_t silenceFramesForEnd = 75;  // Frames of silence to trigger END_OF_SPEECH (75 * 20ms = 1.5s)
    uint16_t speechFramesForStart = 3;  // Frames of speech to confirm speech started
    float adaptiveRate = 0.01f;         // How fast the noise floor adapts
};

/// Initialize VAD with configuration.
void init(const Config& config = Config{});

/// Calibrate noise floor from known silence frames.
/// Call with initial silence at the start of recording.
void calibrate(const int16_t* pcm, size_t sampleCount);

/// Analyze a PCM frame and return the result.
/// Frame should be one Opus frame (320 samples at 16kHz = 20ms).
Result analyze(const int16_t* pcm, size_t sampleCount);

/// Reset VAD state (call when starting a new recording).
void reset();

/// Get the current noise floor estimate (RMS).
float getNoiseFloor();

/// Get the RMS energy of the last analyzed frame.
float getLastEnergy();

/// Check if speech has been detected at all in the current session.
bool hasSpeechStarted();

}  // namespace vad
