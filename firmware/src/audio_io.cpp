#include "audio_io.h"
#include "config.h"
#include "es8311.h"
#include "driver/i2s_std.h"
#include <Arduino.h>

// ES8311 codec — new I2S driver (ESP-IDF 5.x).
// Full-duplex on I2S_NUM_1 (manufacturer's port) with MCLK.
static i2s_chan_handle_t tx_handle = nullptr;
static i2s_chan_handle_t rx_handle = nullptr;

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

    // Max volume + 24dB mic gain (sweet spot: 18dB too quiet, 36dB+ feedback)
    es8311_handle_t es_handle = es8311_create(I2C_NUM_0, ES8311_ADDRESS_0);
    es8311_voice_volume_set(es_handle, 100, NULL);
    es8311_microphone_gain_set(es_handle, ES8311_MIC_GAIN_24DB);

    Serial.println("[Audio] ES8311 codec ready (vol=100, mic=24dB)");
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

size_t audio_io::writeSpeaker(const int16_t* buffer, size_t numSamples) {
    int16_t* stereoBuf = (int16_t*)malloc(numSamples * 2 * sizeof(int16_t));
    if (!stereoBuf) return 0;

    for (size_t i = 0; i < numSamples; i++) {
        stereoBuf[i * 2] = buffer[i];
        stereoBuf[i * 2 + 1] = buffer[i];
    }

    size_t bytesWritten = 0;
    esp_err_t err = i2s_channel_write(
        tx_handle, stereoBuf,
        numSamples * 2 * sizeof(int16_t),
        &bytesWritten, 100
    );
    free(stereoBuf);

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
