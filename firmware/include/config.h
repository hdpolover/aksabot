#pragma once

// ═══════════════════════════════════════════════════════════════
// Aksabot Firmware Configuration
//
// Board: ES3C28P (ESP32-S3 2.8" LCD Display)
//   Source: https://www.lcdwiki.com/2.8inch_ESP32-S3_Display
//   Display: ILI9341V 240x320 SPI (IPS TFT)
//   Touch: FT6336G capacitive I2C
//   Audio: ES8311 codec + FM8002E amplifier (I2S)
//   Storage: MicroSD via SDIO (4-bit)
//   LED: WS2812B RGB (single)
// ═══════════════════════════════════════════════════════════════

// ── Credentials (Wi-Fi, backend URL, device token) ────
// Defined in credentials.h (git-ignored).
// Copy credentials.h.example → credentials.h and fill in your values.
#include "credentials.h"

// ── LCD Display (ILI9341V, SPI) ────────────────────────
// Pin mapping from manufacturer's spi_dev.h
#define LCD_CS    10
#define LCD_DC    46
#define LCD_SCLK  12
#define LCD_MOSI  11
#define LCD_MISO  13
#define LCD_RST   -1
#define LCD_BL    45
#define LCD_WIDTH  240
#define LCD_HEIGHT 320

// ── Touch (FT6336G, I2C) ──────────────────────────────
#define TOUCH_SDA  16
#define TOUCH_SCL  15
#define TOUCH_RST  18
#define TOUCH_INT  17
#define TOUCH_I2C_ADDR 0x38  // FT6336G default address

// ── I2S Audio (ES8311 codec + FM8002E amplifier) ──────
// Pin mapping from manufacturer's echo demo (Example_17)
#define I2S_MCLK   4
#define I2S_BCLK   5
#define I2S_WS     7   // LR select
#define I2S_DOUT   8   // Data out (to speaker via ES8311 DAC)
#define I2S_DIN    6   // Data in (from ES8311 ADC / built-in MEMS mic)
#define AUDIO_EN   1   // Amplifier enable (LOW = enabled, HIGH = disabled)

// Mic is built into the ES8311 codec via I2S_DIN
// No external INMP441 needed!
#define I2S_MIC_SAMPLE_RATE 16000
#define I2S_MIC_BITS        16
#define I2S_MIC_CHANNELS    1

// Legacy aliases for existing code
#define I2S_MIC_BCLK  I2S_BCLK
#define I2S_MIC_WS    I2S_WS
#define I2S_MIC_DATA  I2S_DIN
#define I2S_SPK_BCLK  I2S_BCLK
#define I2S_SPK_WS    I2S_WS
#define I2S_SPK_DATA  I2S_DOUT

// ── MicroSD Card (SDIO 4-bit) ─────────────────────────
// NOTE: This board uses SDIO, not SPI for the SD card.
// The SD library auto-detects SDIO on ESP32-S3.
#define SD_CLK    38
#define SD_CMD    40
#define SD_D0     39
#define SD_D1     41
#define SD_D2     48
#define SD_D3     47

// Legacy SPI aliases for sd_storage.cpp compatibility
// TODO: Update sd_storage to use SD_MMC (SDIO) instead of SPI SD
#define SPI_CLK   SD_CLK
#define SPI_MOSI  SD_CMD
#define SPI_MISO  SD_D0
#define SD_CS     -1    // SDIO doesn't use CS

// ── RGB LED (WS2812B) ─────────────────────────────────
#define LED_PIN   42
#define LED_COUNT 1

// ── Battery ────────────────────────────────────────────
#define BATTERY_ADC 9

// ── Expandable GPIO ───────────────────────────────────
// Available: IO2, IO3, IO14, IO21
#define GPIO_SPARE_1  2
#define GPIO_SPARE_2  3
#define GPIO_SPARE_3  14
#define GPIO_SPARE_4  21

// ── Opus codec ─────────────────────────────────────────
#ifndef OPUS_FRAME_MS
#define OPUS_FRAME_MS 20
#endif
#ifndef OPUS_BITRATE
#define OPUS_BITRATE 16000
#endif
#define OPUS_FRAME_SAMPLES (I2S_MIC_SAMPLE_RATE * OPUS_FRAME_MS / 1000)  // 320

// ── Audio buffers ──────────────────────────────────────
#define AUDIO_RING_BUFFER_SAMPLES 1024
#define OPUS_MAX_FRAME_BYTES 512

// ── Timings ────────────────────────────────────────────
#define WIFI_RECONNECT_BASE_MS   1000
#define WIFI_RECONNECT_MAX_MS    30000
#define WS_RECONNECT_BASE_MS     1000
#define WS_RECONNECT_MAX_MS      30000
