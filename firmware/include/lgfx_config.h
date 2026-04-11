#pragma once

#define LGFX_USE_V1
#include <LovyanGFX.hpp>
#include "config.h"

class LGFX : public lgfx::LGFX_Device {
    lgfx::Panel_ILI9341  _panel;
    lgfx::Bus_SPI        _bus;
    lgfx::Light_PWM      _light;
    lgfx::Touch_FT5x06   _touch;

public:
    LGFX() {
        // SPI bus (display)
        {
            auto cfg = _bus.config();
            cfg.spi_host    = SPI2_HOST;
            cfg.spi_mode    = 0;
            cfg.freq_write  = 40000000;  // 40MHz — 80MHz causes horizontal sliding on ES3C28P
            cfg.freq_read   = 16000000;
            cfg.spi_3wire   = false;
            cfg.use_lock    = true;
            cfg.dma_channel = SPI_DMA_CH_AUTO;
            cfg.pin_sclk    = LCD_SCLK;
            cfg.pin_mosi    = LCD_MOSI;
            cfg.pin_miso    = LCD_MISO;
            cfg.pin_dc      = LCD_DC;
            _bus.config(cfg);
            _panel.setBus(&_bus);
        }

        // Panel (ILI9341V)
        {
            auto cfg = _panel.config();
            cfg.pin_cs          = LCD_CS;
            cfg.pin_rst         = LCD_RST;
            cfg.pin_busy        = -1;
            cfg.panel_width     = LCD_WIDTH;   // 240
            cfg.panel_height    = LCD_HEIGHT;  // 320
            cfg.offset_x        = 0;
            cfg.offset_y        = 0;
            cfg.offset_rotation = 0;
            cfg.invert          = false;
            cfg.rgb_order       = false;       // BGR (ILI9341 default)
            cfg.memory_width    = LCD_WIDTH;
            cfg.memory_height   = LCD_HEIGHT;
            cfg.bus_shared      = false;       // No other device on this SPI bus
            _panel.config(cfg);
        }

        // Touch (FT6336G — FT5x06 family, I2C)
        // Uses I2C port 1 to avoid conflict with ES8311 audio codec on port 0
        {
            auto cfg = _touch.config();
            cfg.i2c_port  = 0;            // Shared with ES8311 codec (same physical I2C bus)
            cfg.i2c_addr  = 0x38;         // FT6336G default
            cfg.pin_sda   = TOUCH_SDA;    // GPIO 16
            cfg.pin_scl   = TOUCH_SCL;    // GPIO 15
            cfg.pin_int   = -1;           // We read TOUCH_INT manually in touch.cpp
            cfg.pin_rst   = TOUCH_RST;    // GPIO 18
            cfg.freq      = 400000;
            cfg.x_min     = 0;
            cfg.x_max     = LCD_WIDTH - 1;   // 239
            cfg.y_min     = 0;
            cfg.y_max     = LCD_HEIGHT - 1;  // 319
            cfg.bus_shared = false;        // Touch is I2C, display is SPI
            _touch.config(cfg);
            _panel.setTouch(&_touch);
        }

        // Backlight (PWM)
        {
            auto cfg = _light.config();
            cfg.pin_bl      = LCD_BL;
            cfg.invert      = false;
            cfg.freq        = 12000;
            cfg.pwm_channel = 0;
            _light.config(cfg);
            _panel.setLight(&_light);
        }

        setPanel(&_panel);
    }
};
