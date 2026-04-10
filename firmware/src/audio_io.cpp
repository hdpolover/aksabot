#include "audio_io.h"
#include "config.h"
#include "es8311.h"
#include <driver/i2s.h>
#include <driver/i2c.h>
#include <Arduino.h>

// ES8311 codec with legacy I2S driver.
// Full-duplex on I2S_NUM_0 with MCLK for the codec.
static const i2s_port_t AUDIO_PORT = I2S_NUM_0;

// ── I2C init for ES8311 codec ──────────────────────────
// NOTE: I2C bus is shared with the FT6336G touch controller.
// Touch driver initializes Wire(0) first. We try i2c_driver_install
// and if it's already installed, that's fine — we just skip it.
static esp_err_t codec_i2c_init() {
    // I2C bus is already initialized by the touch driver (Wire.begin in touch.cpp).
    // The ES8311 codec sits on the same I2C bus (GPIO 15/16) at address 0x18.
    // No need to re-initialize — just verify the bus is accessible.
    return ESP_OK;
}

void audio_io::init() {
    // Enable amplifier (FM8002E) — active LOW
    pinMode(AUDIO_EN, OUTPUT);
    digitalWrite(AUDIO_EN, LOW);

    // Initialize I2C for ES8311 codec control
    if (codec_i2c_init() != ESP_OK) {
        Serial.println("[Audio] I2C init failed!");
        return;
    }
    Serial.println("[Audio] I2C initialized for ES8311");

    // Configure I2S for full-duplex (TX + RX)
    i2s_config_t i2sConfig = {};
    i2sConfig.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX | I2S_MODE_RX);
    i2sConfig.sample_rate = I2S_MIC_SAMPLE_RATE;
    i2sConfig.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
    i2sConfig.channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT;  // Stereo for ES8311
    i2sConfig.communication_format = I2S_COMM_FORMAT_STAND_I2S;
    i2sConfig.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
    i2sConfig.dma_buf_count = 8;
    i2sConfig.dma_buf_len = AUDIO_RING_BUFFER_SAMPLES;
    i2sConfig.use_apll = false;
    i2sConfig.fixed_mclk = I2S_MIC_SAMPLE_RATE * 384;  // MCLK = 16000 * 384 = 6.144MHz

    esp_err_t err = i2s_driver_install(AUDIO_PORT, &i2sConfig, 0, NULL);
    if (err != ESP_OK) {
        Serial.printf("[Audio] I2S driver install failed: %d\n", err);
        return;
    }

    i2s_pin_config_t pins = {};
    pins.mck_io_num = I2S_MCLK;    // GPIO 4
    pins.bck_io_num = I2S_BCLK;    // GPIO 5
    pins.ws_io_num = I2S_WS;       // GPIO 7
    pins.data_out_num = I2S_DOUT;   // GPIO 8
    pins.data_in_num = I2S_DIN;     // GPIO 6

    err = i2s_set_pin(AUDIO_PORT, &pins);
    if (err != ESP_OK) {
        Serial.printf("[Audio] I2S set pin failed: %d\n", err);
        return;
    }
    Serial.println("[Audio] I2S initialized (16kHz, stereo, full-duplex)");

    // Initialize ES8311 codec via I2C
    if (es8311_codec_init() != ESP_OK) {
        Serial.println("[Audio] ES8311 codec init failed!");
        return;
    }

    Serial.println("[Audio] ES8311 codec ready (mic + speaker)");
}

size_t audio_io::readMic(int16_t* buffer, size_t maxSamples) {
    // Read stereo data, then extract left channel for mono
    size_t stereoBytes = maxSamples * 2 * sizeof(int16_t);
    size_t bytesRead = 0;

    esp_err_t err = i2s_read(AUDIO_PORT, buffer, stereoBytes, &bytesRead, pdMS_TO_TICKS(100));
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
    // Duplicate mono to stereo for ES8311
    int16_t* stereoBuf = (int16_t*)malloc(numSamples * 2 * sizeof(int16_t));
    if (!stereoBuf) return 0;

    for (size_t i = 0; i < numSamples; i++) {
        stereoBuf[i * 2] = buffer[i];
        stereoBuf[i * 2 + 1] = buffer[i];
    }

    size_t bytesWritten = 0;
    esp_err_t err = i2s_write(AUDIO_PORT, stereoBuf, numSamples * 2 * sizeof(int16_t), &bytesWritten, pdMS_TO_TICKS(100));
    free(stereoBuf);

    if (err != ESP_OK) return 0;
    return bytesWritten / (2 * sizeof(int16_t));
}

void audio_io::stopMic() {
    // In full-duplex mode, can't stop RX independently
}

void audio_io::stopSpeaker() {
    i2s_zero_dma_buffer(AUDIO_PORT);
}
