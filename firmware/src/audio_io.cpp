#include "audio_io.h"
#include "config.h"
#include <driver/i2s.h>
#include <Arduino.h>

// I2S port assignments: mic on I2S_NUM_0, speaker on I2S_NUM_1
static const i2s_port_t MIC_PORT = I2S_NUM_0;
static const i2s_port_t SPK_PORT = I2S_NUM_1;

void audio_io::init() {
    // ── Mic (I2S input) ──────────────────────────────────
    i2s_config_t micConfig = {};
    micConfig.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX);
    micConfig.sample_rate = I2S_MIC_SAMPLE_RATE;
    micConfig.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
    micConfig.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
    micConfig.communication_format = I2S_COMM_FORMAT_STAND_I2S;
    micConfig.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
    micConfig.dma_buf_count = 4;
    micConfig.dma_buf_len = AUDIO_RING_BUFFER_SAMPLES;
    micConfig.use_apll = false;

    i2s_driver_install(MIC_PORT, &micConfig, 0, NULL);

    i2s_pin_config_t micPins = {};
    micPins.bck_io_num = I2S_MIC_BCLK;
    micPins.ws_io_num = I2S_MIC_WS;
    micPins.data_in_num = I2S_MIC_DATA;
    micPins.data_out_num = I2S_PIN_NO_CHANGE;
    i2s_set_pin(MIC_PORT, &micPins);

    Serial.println("[Audio] Mic I2S initialized");

    // ── Speaker (I2S output) ──────────────────────────────
    i2s_config_t spkConfig = {};
    spkConfig.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX);
    spkConfig.sample_rate = I2S_MIC_SAMPLE_RATE;  // same rate as mic/TTS
    spkConfig.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
    spkConfig.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
    spkConfig.communication_format = I2S_COMM_FORMAT_STAND_I2S;
    spkConfig.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
    spkConfig.dma_buf_count = 4;
    spkConfig.dma_buf_len = AUDIO_RING_BUFFER_SAMPLES;
    spkConfig.use_apll = false;

    i2s_driver_install(SPK_PORT, &spkConfig, 0, NULL);

    i2s_pin_config_t spkPins = {};
    spkPins.bck_io_num = I2S_SPK_BCLK;
    spkPins.ws_io_num = I2S_SPK_WS;
    spkPins.data_out_num = I2S_SPK_DATA;
    spkPins.data_in_num = I2S_PIN_NO_CHANGE;
    i2s_set_pin(SPK_PORT, &spkPins);

    Serial.println("[Audio] Speaker I2S initialized");
}

size_t audio_io::readMic(int16_t* buffer, size_t maxSamples) {
    size_t bytesRead = 0;
    size_t bytesToRead = maxSamples * sizeof(int16_t);

    esp_err_t err = i2s_read(MIC_PORT, buffer, bytesToRead, &bytesRead, portMAX_DELAY);
    if (err != ESP_OK) {
        Serial.printf("[Audio] Mic read error: %d\n", err);
        return 0;
    }

    return bytesRead / sizeof(int16_t);
}

size_t audio_io::writeSpeaker(const int16_t* buffer, size_t numSamples) {
    size_t bytesWritten = 0;
    size_t bytesToWrite = numSamples * sizeof(int16_t);

    esp_err_t err = i2s_write(SPK_PORT, buffer, bytesToWrite, &bytesWritten, portMAX_DELAY);
    if (err != ESP_OK) {
        Serial.printf("[Audio] Speaker write error: %d\n", err);
        return 0;
    }

    return bytesWritten / sizeof(int16_t);
}

void audio_io::stopMic() {
    i2s_stop(MIC_PORT);
}

void audio_io::stopSpeaker() {
    i2s_stop(SPK_PORT);
    i2s_zero_dma_buffer(SPK_PORT);
}
