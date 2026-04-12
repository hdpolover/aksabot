#pragma once
#include <cstdint>
#include <functional>

/// Wake word detection module.
///
/// Energy-based speech detector: triggers when a sound segment of the right
/// duration (400ms–1.2s) crosses the adaptive noise floor threshold.
/// Any speech phrase of that length will trigger it — not specifically "hey aksa".
///
/// Detection quality depends on mic gain (set in audio_io::init via ES8311_MIC_GAIN_*).
/// Higher gain → wider margin between voice and threshold → more reliable detection.
/// Current tuning targets ES8311_MIC_GAIN_42DB.
///
/// The detector piggybacks on the audio capture loop (Core 0).
/// Mic frames are fed via wake_word_processMicFrame() — no separate task.
///
/// Usage:
///   wake_word::init();
///   wake_word::onWake([]() {
///       // Start recording — same flow as touch HOLD_START
///   });
///   wake_word::startListening();
namespace wake_word {

/// Callback fired when wake word is detected.
using WakeCallback = std::function<void()>;

/// Initialize wake word detection.
void init();

/// Register callback for wake word detection.
void onWake(WakeCallback cb);

/// Start listening for wake word (creates background task if needed).
/// Call when bot is IDLE and ready for interaction.
void startListening();

/// Stop listening (during recording, speaking, or sleep).
/// Pauses the background task without destroying it.
void stopListening();

/// Check if currently listening for wake word.
bool isListening();

/// Set detection sensitivity (0.0 = strict, 1.0 = loose). Default 0.5.
void setSensitivity(float sensitivity);

}  // namespace wake_word

/// Process a mic PCM frame for wake word detection.
/// Called from audioCaptureLoop when bot is IDLE (no separate task needed).
/// Returns true if wake word was detected.
bool wake_word_processMicFrame(const int16_t* pcm, size_t sampleCount);
