#pragma once

// ── Wi-Fi ──────────────────────────────────────────────
// Phase 1: compile-time from env vars. Phase 4+: NVS via BLE provisioning.
#ifndef WIFI_SSID
#define WIFI_SSID "changeme"
#endif
#ifndef WIFI_PASS
#define WIFI_PASS "changeme"
#endif

// ── Backend ────────────────────────────────────────────
#ifndef BACKEND_WS_URL
#define BACKEND_WS_URL "ws://192.168.1.100:4280/ws"
#endif
#ifndef DEVICE_TOKEN
#define DEVICE_TOKEN "changeme"
#endif

// ── I2S Microphone pins ────────────────────────────────
#ifndef I2S_MIC_BCLK
#define I2S_MIC_BCLK 5
#endif
#ifndef I2S_MIC_WS
#define I2S_MIC_WS 6
#endif
#ifndef I2S_MIC_DATA
#define I2S_MIC_DATA 7
#endif
#define I2S_MIC_SAMPLE_RATE 16000
#define I2S_MIC_BITS        16
#define I2S_MIC_CHANNELS    1

// ── I2S Speaker pins ───────────────────────────────────
#ifndef I2S_SPK_BCLK
#define I2S_SPK_BCLK 15
#endif
#ifndef I2S_SPK_WS
#define I2S_SPK_WS 16
#endif
#ifndef I2S_SPK_DATA
#define I2S_SPK_DATA 17
#endif

// ── SPI bus (shared: display, touch, SD) ───────────────
#ifndef SPI_CLK
#define SPI_CLK 12
#endif
#ifndef SPI_MOSI
#define SPI_MOSI 11
#endif
#ifndef SPI_MISO
#define SPI_MISO 13
#endif
#ifndef SD_CS
#define SD_CS 10
#endif

// ── Opus codec ─────────────────────────────────────────
#ifndef OPUS_FRAME_MS
#define OPUS_FRAME_MS 20
#endif
#ifndef OPUS_BITRATE
#define OPUS_BITRATE 16000
#endif
// Samples per Opus frame: sample_rate * frame_ms / 1000
#define OPUS_FRAME_SAMPLES (I2S_MIC_SAMPLE_RATE * OPUS_FRAME_MS / 1000)  // 320

// ── Audio buffers ──────────────────────────────────────
// Ring buffer size for I2S DMA (in samples)
#define AUDIO_RING_BUFFER_SAMPLES 1024
// Max Opus encoded frame size (bytes)
#define OPUS_MAX_FRAME_BYTES 512

// ── Timings ────────────────────────────────────────────
#define WIFI_RECONNECT_BASE_MS   1000
#define WIFI_RECONNECT_MAX_MS    30000
#define WS_RECONNECT_BASE_MS     1000
#define WS_RECONNECT_MAX_MS      30000
