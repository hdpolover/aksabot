#include "audio_io.h"
#include "config.h"
#include "nvs_store.h"
#include "es8311.h"
#include "driver/i2s_std.h"
#include <Arduino.h>
#include <math.h>

// ES8311 codec — new I2S driver (ESP-IDF 5.x).
// Full-duplex on I2S_NUM_1 (manufacturer's port) with MCLK.
static i2s_chan_handle_t tx_handle = nullptr;
static i2s_chan_handle_t rx_handle = nullptr;

// Software volume scale (0.0 – 1.0). Applied to every PCM sample in
// writeSpeaker() so that ALL audio paths (TTS, SFX, resilience, emotion)
// are attenuated uniformly. ES8311 is held at a fixed hardware level
// (HW_VOLUME_FIXED) so the user-facing volume knob maps 1:1 to PCM amplitude.
static float   s_volumeScale   = 1.0f;
static const uint8_t HW_VOLUME_FIXED = 75;  // safe max — >82 distorts on this amp

void audio_io::init() {
    // Enable amplifier (FM8002E) — active LOW
    pinMode(AUDIO_EN, OUTPUT);
    digitalWrite(AUDIO_EN, LOW);

    Serial.println("[Audio] I2C ready for ES8311 (shared with touch on Wire)");

    // ── 1. Create I2S channel pair (full-duplex, I2S_NUM_1) ──────────────
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
    chan_cfg.auto_clear = true;

    esp_err_t err = i2s_new_channel(&chan_cfg, &tx_handle, &rx_handle);
    if (err != ESP_OK) {
        Serial.printf("[Audio] i2s_new_channel failed: %d\n", err);
        return;
    }

    // ── 2. Standard mode config (shared clock/slot for full-duplex) ──────
    i2s_std_config_t std_cfg = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(I2S_MIC_SAMPLE_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(
            I2S_DATA_BIT_WIDTH_16BIT,
            I2S_SLOT_MODE_STEREO
        ),
        .gpio_cfg = {
            .mclk = (gpio_num_t)I2S_MCLK,
            .bclk = (gpio_num_t)I2S_BCLK,
            .ws   = (gpio_num_t)I2S_WS,
            .dout = (gpio_num_t)I2S_DOUT,
            .din  = (gpio_num_t)I2S_DIN,
            .invert_flags = {
                .mclk_inv = false,
                .bclk_inv = false,
                .ws_inv   = false,
            },
        },
    };
    std_cfg.clk_cfg.mclk_multiple = I2S_MCLK_MULTIPLE_384;

    err = i2s_channel_init_std_mode(tx_handle, &std_cfg);
    if (err != ESP_OK) {
        Serial.printf("[Audio] TX init failed: %d\n", err);
        return;
    }

    err = i2s_channel_init_std_mode(rx_handle, &std_cfg);
    if (err != ESP_OK) {
        Serial.printf("[Audio] RX init failed: %d\n", err);
        return;
    }

    // ── 3. Enable both channels before ES8311 init ───────────────────────
    i2s_channel_enable(tx_handle);
    i2s_channel_enable(rx_handle);

    Serial.println("[Audio] I2S initialized (16kHz, stereo, full-duplex, I2S_NUM_1)");

    // ── 4. Initialize ES8311 codec via I2C ──────────────────────────────
    if (es8311_codec_init() != ESP_OK) {
        Serial.println("[Audio] ES8311 codec init failed!");
        return;
    }

    // Fix ES8311 hardware output at HW_VOLUME_FIXED — all volume control is
    // done in software (writeSpeaker scales PCM by s_volumeScale) so that
    // every audio source (TTS, SFX, resilience clips) respects the same knob.
    es8311_handle_t es_handle = es8311_create(I2C_NUM_0, ES8311_ADDRESS_0);
    es8311_voice_volume_set(es_handle, HW_VOLUME_FIXED, NULL);
    es8311_microphone_gain_set(es_handle, ES8311_MIC_GAIN_42DB);

    // Restore user volume as software scale from NVS.
    uint8_t vol = nvs_store::getVolume();
    setVolume(vol);

    Serial.printf("[Audio] ES8311 codec ready (hw=%d%%, sw=%d%%, mic=42dB)\n",
                  HW_VOLUME_FIXED, vol);
}

size_t audio_io::readMic(int16_t* buffer, size_t maxSamples) {
    size_t stereoBytes = maxSamples * 2 * sizeof(int16_t);
    size_t bytesRead = 0;

    esp_err_t err = i2s_channel_read(rx_handle, buffer, stereoBytes, &bytesRead, 100);
    if (err != ESP_OK) return 0;

    // Extract left channel (every other sample) in-place
    size_t stereoSamples = bytesRead / sizeof(int16_t);
    size_t monoSamples = stereoSamples / 2;
    for (size_t i = 0; i < monoSamples; i++) {
        buffer[i] = buffer[i * 2];
    }

    return monoSamples;
}

// Static stereo buffer — avoids malloc/free per frame which fragments heap
static int16_t speakerStereoBuf[320 * 2];  // max OPUS_FRAME_SAMPLES * 2 channels

size_t audio_io::writeSpeaker(const int16_t* buffer, size_t numSamples) {
    if (numSamples > 320) numSamples = 320;  // safety clamp

    for (size_t i = 0; i < numSamples; i++) {
        // Apply software volume so all audio sources (TTS, SFX, resilience)
        // are scaled uniformly. Clamp to prevent int16 overflow.
        int32_t scaled = (int32_t)((float)buffer[i] * s_volumeScale);
        if (scaled >  32767) scaled =  32767;
        if (scaled < -32768) scaled = -32768;
        int16_t s = (int16_t)scaled;
        speakerStereoBuf[i * 2]     = s;
        speakerStereoBuf[i * 2 + 1] = s;
    }

    size_t bytesWritten = 0;
    esp_err_t err = i2s_channel_write(
        tx_handle, speakerStereoBuf,
        numSamples * 2 * sizeof(int16_t),
        &bytesWritten, portMAX_DELAY
    );

    if (err != ESP_OK) return 0;
    return bytesWritten / (2 * sizeof(int16_t));
}

void audio_io::stopMic() {
    // In full-duplex mode, leave RX running to avoid DMA stalls
}

void audio_io::stopSpeaker() {
    // Flush TX DMA by cycling disable/enable
    if (tx_handle) {
        i2s_channel_disable(tx_handle);
        i2s_channel_enable(tx_handle);
    }
}

size_t audio_io::readRawStereo(int16_t* buffer, size_t maxSamples) {
    size_t bytesToRead = maxSamples * 2 * sizeof(int16_t);
    size_t bytesRead = 0;
    esp_err_t err = i2s_channel_read(rx_handle, buffer, bytesToRead, &bytesRead, 100);
    if (err != ESP_OK) return 0;
    return bytesRead / (2 * sizeof(int16_t));
}

size_t audio_io::writeRawStereo(const int16_t* buffer, size_t numSamples) {
    size_t bytesToWrite = numSamples * 2 * sizeof(int16_t);
    size_t bytesWritten = 0;
    i2s_channel_write(tx_handle, buffer, bytesToWrite, &bytesWritten, portMAX_DELAY);
    return bytesWritten / (2 * sizeof(int16_t));
}

void audio_io::flushSpeaker() {
    if (tx_handle) {
        i2s_channel_disable(tx_handle);
        i2s_channel_enable(tx_handle);
    }
}

void audio_io::setVolume(uint8_t percent) {
    if (percent > 100) percent = 100;
    // Exponential (dB) curve — industry standard for audio volume control.
    // Maps 1–100% linearly across 30 dB: 100% = 0 dB (full), 50% ≈ −15 dB,
    // 20% ≈ −24 dB (soft but audible), 0% = muted.
    // 40 dB range made 20% inaudible on this amp; 20 dB range made 20% too loud.
    // Applied in software PCM so all audio sources (TTS, SFX, resilience) scale together.
    if (percent == 0) {
        s_volumeScale = 0.0f;
    } else {
        float db = ((float)percent / 100.0f - 1.0f) * 30.0f;
        s_volumeScale = powf(10.0f, db / 20.0f);
    }
    Serial.printf("[Audio] Volume %d%% → %.1f dB → scale %.4f\n",
                  percent,
                  (percent == 0) ? -99.0f : ((float)percent / 100.0f - 1.0f) * 30.0f,
                  s_volumeScale);
}
