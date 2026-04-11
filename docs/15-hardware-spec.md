# 15 — Hardware Specification: ES3C28P

> Source: ES3C28P_ES2N28P_Specification_V1.0.pdf (ShenZhen QDtech)
> Board SKU: **ES3C28P** (with capacitive touch)
> Wiki: https://www.lcdwiki.com/2.8inch_ESP32-S3_Display

---

## 1. Overview

The ES3C28P is a 2.8-inch IPS display module with an integrated ESP32-S3 MCU.
It includes a capacitive touch screen, audio codec with speaker amplifier, MEMS
microphone, MicroSD slot, RGB LED, battery charging circuit, and multiple
expansion interfaces — all on a single 50x86mm PCB.

This is the target hardware for Aksabot.

---

## 2. ESP32-S3 MCU

| Parameter | Value |
|-----------|-------|
| Chip | ESP32-S3 |
| CPU | Xtensa LX7, 32-bit, dual-core |
| Max clock | 240 MHz |
| ROM | 384 KB |
| SRAM | 512 KB |
| RTC SRAM | 16 KB |
| PSRAM | 8 MB (internal, OPI) |
| Flash | 16 MB (external, SPI) |
| Wi-Fi | 2.4 GHz, 802.11 b/g/n |
| Bluetooth | BT 5.0 BR/EDR + BLE |
| Operating voltage | 3.0–3.6 V |
| Operating temp | -40 to +85 C |

**Model designation: N16R8** (16MB Flash, 8MB PSRAM)

---

## 3. Display (ILI9341V)

| Parameter | Value |
|-----------|-------|
| Size | 2.8 inch |
| Type | IPS TFT |
| Resolution | 240 x RGB x 320 |
| Active area | 43.20 x 57.60 mm |
| Colors | Max 262K (RGB666), typical 56K (RGB565) |
| Driver IC | ILI9341V |
| Interface | 4-line SPI (directly wired to ESP32-S3) |
| Pixel pitch | 0.153 x 0.153 mm |
| Viewing angle | All directions (IPS) |
| Backlight | 4x white LED, ~280 cd/m2 typical |
| Backlight control | GPIO45 (HIGH = on, LOW = off, PWM for dimming) |
| Reset | Shared with ESP32-S3 CHIP_PU (no software-only LCD reset) |
| Operating temp | -30 to +80 C |

### Display SPI Pin Mapping

| Signal | GPIO | Description |
|--------|------|-------------|
| CS | 10 | Chip select, active low |
| DC | 46 | Data/command select (HIGH=data, LOW=command) |
| SCLK | 12 | SPI clock |
| MOSI | 11 | SPI data write |
| MISO | 13 | SPI data read |
| RST | -1 | Shared with CHIP_PU, not independently controllable |
| BL | 45 | Backlight enable |

---

## 4. Touch Screen (FT6336G)

| Parameter | Value |
|-----------|-------|
| Type | Capacitive (G+F structure) |
| Driver IC | FT6336G |
| Interface | I2C (device address: 0x38) |
| Active area | 43.20 x 57.60 mm |
| Operating temp | -30 to +80 C |

### Touch I2C Pin Mapping

| Signal | GPIO | Description |
|--------|------|-------------|
| SDA | 16 | I2C data (shared with audio codec + I2C expansion) |
| SCL | 15 | I2C clock (shared with audio codec + I2C expansion) |
| RST | 18 | Reset, active low |
| INT | 17 | Interrupt, goes LOW on touch event |

> **Important:** The I2C bus (GPIO16/15) is shared between the touch controller,
> audio codec IC, and the external I2C expansion header. All three coexist on the
> same bus at different addresses.

---

## 5. Audio (ES8311 Codec + FM8002E Amplifier)

The board has a built-in ES8311 audio codec connected via I2S, a downward-facing
MEMS microphone for audio input, and an FM8002E Class-D power amplifier for
speaker output.

### I2S Pin Mapping

| Signal | GPIO | Description |
|--------|------|-------------|
| MCLK | 4 | Master clock |
| BCLK | 5 | Bit clock |
| DOUT | 6 | Data out (from codec to ESP32 — mic input) |
| WS | 7 | Word select / LR channel (HIGH=right, LOW=left) |
| DIN | 8 | Data in (from ESP32 to codec — speaker output) |

### Amplifier Control

| Signal | GPIO | Description |
|--------|------|-------------|
| PA_EN | 1 | Power amplifier enable — **LOW = enabled**, HIGH = disabled |

### Speaker Specifications

| Parameter | Value |
|-----------|-------|
| Max power (8 ohm) | 1.5 W |
| Max power (4 ohm) | 2.0 W |
| Interface | 1.25mm 2P socket |

### Audio Codec I2C

The ES8311 codec is configured via I2C, sharing the same bus as touch:
- SDA: GPIO16
- SCL: GPIO15

---

## 6. MicroSD Card (SDIO 4-bit)

The SD card slot uses **SDIO mode** (not SPI). Use the `SD_MMC` library on
ESP32-S3, not the SPI-based `SD` library.

### SDIO Pin Mapping

| Signal | GPIO | Description |
|--------|------|-------------|
| CLK | 38 | SDIO clock |
| CMD | 40 | SDIO command |
| DATA0 | 39 | Data bit 0 |
| DATA1 | 41 | Data bit 1 |
| DATA2 | 48 | Data bit 2 |
| DATA3 | 47 | Data bit 3 |

> No CS pin — SDIO doesn't use chip select.

---

## 7. Battery & Power

### Battery Charging

| Parameter | Value |
|-----------|-------|
| Input voltage | 4.2–6.5 V (typical 5.0 V via USB-C) |
| Max charge current | 500 mA (actual ~290 mA) |
| Saturation voltage | 4.24 V |
| Max charge IC temp | 62 C |
| Battery type | 3.7V lithium polymer only |
| Battery ADC | GPIO9 |
| Interface | 1.25mm 2P socket (watch polarity!) |

### Power Consumption

| State | Current (mA) | Power (W) |
|-------|-------------|-----------|
| ESP32-S3 in reset | ~0 | ~0 |
| Display only | 140 | 0.7 |
| Display + speaker + charging | 560 | 2.8 |
| Backlight alone | 79 | — |

---

## 8. RGB LED

| Parameter | Value |
|-----------|-------|
| Type | WS2812-style (built-in control IC, single data line) |
| GPIO | 42 |
| Count | 1 |
| Colors | Red, green, blue (individually addressable via timing protocol) |

---

## 9. Buttons

| Button | GPIO | Behavior |
|--------|------|----------|
| BOOT | 0 | Active LOW. Hold during power-on to enter download mode. Usable as general button during normal operation. |
| RESET | CHIP_PU | Active LOW. Resets entire ESP32-S3 + LCD. |

---

## 10. Expansion & Connectivity

### USB (Type-C)

Connected to ESP32-S3 internal USB bus (GPIO19/20). Provides:
- Program download
- USB CDC serial debug (Win10+ only for virtual COM port)
- 5V power input

### UART Header (1.25mm 4P)

| Signal | GPIO |
|--------|------|
| TX0 | 43 |
| RX0 | 44 |

Can be used with external USB-to-serial adapter. Also usable as general IO if
UART is not needed.

### I2C Expansion Header (1.25mm 4P)

Shared bus with touch + audio codec (GPIO16 SDA, GPIO15 SCL). Can connect
additional I2C peripherals at non-conflicting addresses.

### Spare GPIO Header (1.25mm 4P)

| GPIO | Notes |
|------|-------|
| 2 | General purpose, can also serve as SPI |
| 3 | General purpose, can also serve as SPI |
| 14 | General purpose, can also serve as SPI |
| 21 | General purpose, can also serve as SPI |

---

## 11. Physical Dimensions

| Variant | PCB Size (mm) | Total Thickness (mm) | Weight (g) |
|---------|---------------|----------------------|------------|
| ES3C28P (touch) | 50.00 x 86.00 | 5.60 | 86 |
| ES3N28P (no touch) | 50.00 x 86.00 | 4.40 | 78 |

Mounting holes: 42.00 x 78.00 mm spacing, 3.50mm diameter holes.

---

## 12. Complete GPIO Allocation

| GPIO | Function | Shared? |
|------|----------|---------|
| 0 | BOOT button | — |
| 1 | Audio PA enable (LOW=on) | — |
| 2 | Spare IO | — |
| 3 | Spare IO | — |
| 4 | I2S MCLK | — |
| 5 | I2S BCLK | — |
| 6 | I2S DOUT (mic data from codec) | — |
| 7 | I2S WS (LR select) | — |
| 8 | I2S DIN (speaker data to codec) | — |
| 9 | Battery voltage ADC | — |
| 10 | LCD CS | — |
| 11 | LCD MOSI (SPI data write) | — |
| 12 | LCD SCLK (SPI clock) | — |
| 13 | LCD MISO (SPI data read) | — |
| 14 | Spare IO | — |
| 15 | I2C SCL | Touch + codec + expansion |
| 16 | I2C SDA | Touch + codec + expansion |
| 17 | Touch INT | — |
| 18 | Touch RST | — |
| 19 | USB D- | — |
| 20 | USB D+ | — |
| 21 | Spare IO | — |
| 26–37 | PSRAM + Flash (internal, do not use) | PSRAM + Flash |
| 38 | SD CLK | — |
| 39 | SD DATA0 | — |
| 40 | SD CMD | — |
| 41 | SD DATA1 | — |
| 42 | RGB LED (WS2812) | — |
| 43 | UART TX0 | — |
| 44 | UART RX0 | — |
| 45 | LCD backlight | — |
| 46 | LCD DC | — |
| 47 | SD DATA3 | — |
| 48 | SD DATA2 | — |

---

## 13. Accessories Included

- 1x 4P 1.25mm to 2.54mm terminal wire (20cm)
- 1x USB Type-C data/power cable (~1m)

---

## 14. Relevance to Aksabot Firmware

All pin definitions in `firmware/include/config.h` have been verified against this
specification. Key notes for hardware integration:

1. **SD card must use SDIO** — migrate `sd_storage.cpp` from SPI `SD` library to
   `SD_MMC` when testing on real hardware.
2. **I2C bus is shared** — touch (0x38), ES8311 codec, and expansion header all
   share GPIO16/15. Use proper I2C addressing and avoid bus conflicts.
3. **LCD has no independent reset** — tied to CHIP_PU. Software cannot reset the
   display without resetting the entire MCU.
4. **Amplifier enable is inverted** — GPIO1 LOW enables the speaker amp. Must be
   pulled LOW before any audio playback.
5. **Battery ADC on GPIO9** — use for battery level monitoring. 3.7V LiPo,
   saturation at 4.24V.
6. **USB CDC requires Win10+** — for development on older Windows, use the UART
   header with an external USB-to-serial adapter.
