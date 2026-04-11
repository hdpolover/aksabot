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

/// Read raw stereo frame from I2S (for echo recording).
/// Buffer must hold maxSamples * 2 int16 (stereo pairs).
/// Returns number of stereo sample pairs read.
size_t readRawStereo(int16_t* buffer, size_t maxSamples);

/// Write raw stereo frame to I2S (for echo playback).
/// Buffer has numSamples * 2 int16 (stereo pairs).
/// Uses portMAX_DELAY for complete write (no dropped frames).
size_t writeRawStereo(const int16_t* buffer, size_t numSamples);

/// Flush TX DMA (call before playback to clear stale data).
void flushSpeaker();

/// Set speaker volume (0-100). Applied to ES8311 codec.
void setVolume(uint8_t percent);

}  // namespace audio_io
