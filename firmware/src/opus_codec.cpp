#include "opus_codec.h"
#include "config.h"
#include <opus.h>
#include <Arduino.h>

static OpusEncoder* encoder = nullptr;
static OpusDecoder* decoder = nullptr;

bool opus_codec::init() {
    int err;

    encoder = opus_encoder_create(
        I2S_MIC_SAMPLE_RATE,
        I2S_MIC_CHANNELS,
        OPUS_APPLICATION_VOIP,
        &err
    );
    if (err != OPUS_OK || !encoder) {
        Serial.printf("[Opus] Encoder init failed: %s\n", opus_strerror(err));
        return false;
    }

    // Configure for low-latency speech
    opus_encoder_ctl(encoder, OPUS_SET_BITRATE(OPUS_BITRATE));
    opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(5));       // balanced CPU/quality
    opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    opus_encoder_ctl(encoder, OPUS_SET_DTX(0));              // DTX off — always send real frames for STT

    decoder = opus_decoder_create(
        I2S_MIC_SAMPLE_RATE,
        I2S_MIC_CHANNELS,
        &err
    );
    if (err != OPUS_OK || !decoder) {
        Serial.printf("[Opus] Decoder init failed: %s\n", opus_strerror(err));
        return false;
    }

    Serial.printf("[Opus] Initialized — %dHz, %d ch, %d bps, %dms frames\n",
                  I2S_MIC_SAMPLE_RATE, I2S_MIC_CHANNELS, OPUS_BITRATE, OPUS_FRAME_MS);
    return true;
}

int opus_codec::encode(const int16_t* pcm, uint8_t* output, size_t outputMaxLen) {
    if (!encoder) return -1;

    int bytes = opus_encode(
        encoder,
        pcm,
        OPUS_FRAME_SAMPLES,
        output,
        (opus_int32)outputMaxLen
    );

    if (bytes < 0) {
        Serial.printf("[Opus] Encode error: %s\n", opus_strerror(bytes));
        return -1;
    }

    return bytes;
}

int opus_codec::decode(const uint8_t* opusData, size_t opusLen, int16_t* pcmOutput, size_t pcmMaxSamples) {
    if (!decoder) return -1;

    int samples = opus_decode(
        decoder,
        opusData,
        (opus_int32)opusLen,
        pcmOutput,
        (int)pcmMaxSamples,
        0  // no FEC
    );

    if (samples < 0) {
        Serial.printf("[Opus] Decode error: %s\n", opus_strerror(samples));
        return -1;
    }

    return samples;
}

void opus_codec::deinit() {
    if (encoder) {
        opus_encoder_destroy(encoder);
        encoder = nullptr;
    }
    if (decoder) {
        opus_decoder_destroy(decoder);
        decoder = nullptr;
    }
}
