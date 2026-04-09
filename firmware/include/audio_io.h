#pragma once
#include <cstdint>
#include <cstddef>

namespace audio_io {

/// Initialize I2S for both mic input and speaker output.
void init();

/// Read one Opus frame worth of PCM samples from the microphone.
/// Returns number of samples read (should be OPUS_FRAME_SAMPLES).
/// Buffer must hold at least OPUS_FRAME_SAMPLES * sizeof(int16_t) bytes.
size_t readMic(int16_t* buffer, size_t maxSamples);

/// Write PCM samples to the speaker.
/// Returns number of samples written.
size_t writeSpeaker(const int16_t* buffer, size_t numSamples);

/// Stop mic input (call when recording ends).
void stopMic();

/// Stop speaker output (call on interrupt or end of playback).
void stopSpeaker();

}  // namespace audio_io
