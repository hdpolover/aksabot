#pragma once
#include <cstdint>
#include <cstddef>

namespace opus_codec {

/// Initialize Opus encoder and decoder.
/// Returns true on success.
bool init();

/// Encode one frame of PCM samples to Opus.
/// pcm: input PCM samples (OPUS_FRAME_SAMPLES int16_t values)
/// output: output buffer (must be at least OPUS_MAX_FRAME_BYTES)
/// Returns number of bytes written to output, or -1 on error.
int encode(const int16_t* pcm, uint8_t* output, size_t outputMaxLen);

/// Decode one Opus frame to PCM samples.
/// opusData: input Opus frame
/// opusLen: input length in bytes
/// pcmOutput: output buffer (must hold at least OPUS_FRAME_SAMPLES int16_t values)
/// Returns number of PCM samples decoded, or -1 on error.
int decode(const uint8_t* opusData, size_t opusLen, int16_t* pcmOutput, size_t pcmMaxSamples);

/// Clean up encoder/decoder resources.
void deinit();

}  // namespace opus_codec
