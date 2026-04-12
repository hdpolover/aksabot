#pragma once
#include <cstdint>
#include <functional>

/// Wake word detection module.
///
/// Continuously monitors microphone audio for the wake phrase "Hey Aksa".
/// When detected, fires a callback to trigger hands-free recording.
///
/// Implementation uses an energy-based keyword spotting approach:
///   1. Mic audio is continuously read in a background FreeRTOS task
///   2. Audio energy is monitored for speech onset
///   3. When speech is detected, a short buffer (~2s) is captured
///   4. The buffer is sent to the backend for wake word verification
///
/// The detection runs on Core 0 alongside the audio capture task,
/// sharing the I2S mic input.
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
