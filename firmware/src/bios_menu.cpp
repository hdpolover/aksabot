#include "bios_menu.h"
#include "config.h"
#include "lgfx_config.h"
#include "touch.h"
#include "audio_io.h"
#include "nvs_store.h"
#include "state.h"
#include "sd_storage.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_system.h>
#include <esp_chip_info.h>
#include <math.h>

extern LGFX tft;

// ── Colors ────────────────────────────────────────────────
static const uint16_t BG     = TFT_BLACK;
static const uint16_t WHITE  = TFT_WHITE;
static const uint16_t CYAN   = TFT_WHITE;
static const uint16_t GREEN  = 0x07E0;
static const uint16_t RED    = TFT_RED;
static const uint16_t YELLOW = TFT_YELLOW;
static const uint16_t DIM    = 0x8C71;

static const int CX = LCD_WIDTH / 2;

// ── Drawing helpers ───────────────────────────────────────

static void cls() { tft.fillScreen(BG); }

static void drawCentered(const char* text, int y, uint16_t color, float size = 1.0) {
    tft.setTextColor(color);
    tft.setFont(&fonts::FreeSans9pt7b);
    tft.setTextSize(size);
    tft.setTextDatum(lgfx::top_center);
    tft.drawString(text, CX, y);
}

static void drawSmall(const char* text, int y, uint16_t color) {
    tft.setTextColor(color);
    tft.setFont(&fonts::Font2);
    tft.setTextSize(1);
    tft.setTextDatum(lgfx::top_center);
    tft.drawString(text, CX, y);
}

static void drawLeft(const char* text, int x, int y, uint16_t color) {
    tft.setTextColor(color);
    tft.setFont(&fonts::Font2);
    tft.setTextSize(1);
    tft.setTextDatum(lgfx::top_left);
    tft.drawString(text, x, y);
}

static void drawRight(const char* text, int x, int y, uint16_t color) {
    tft.setTextColor(color);
    tft.setFont(&fonts::Font2);
    tft.setTextSize(1);
    tft.setTextDatum(lgfx::top_right);
    tft.drawString(text, x, y);
}

// ── Input ─────────────────────────────────────────────────
// Uses the touch driver (tick/isTouched) for reliable debounced detection,
// then reads coordinates via getTouch for hit testing.
// BOOT button (GPIO 0) for back.

static bool bootPressed() {
    return digitalRead(BOOT_BUTTON_PIN) == LOW;
}

static void waitBootRelease() {
    while (bootPressed()) delay(15);
    delay(80);
}

// Poll touch via direct I2C (tft.getTouch) — bypasses the INT-pin debounce
// pipeline which is unreliable for several seconds after FT6336G reset.
static int waitTapY() {
    // Wait for finger-up first (debounce from previous tap)
    lgfx::touch_point_t tp;
    while (tft.getTouch(&tp, 1) > 0) delay(15);

    for (;;) {
        // Also accept serial simulation + BOOT button
        touch::processSerial(millis());
        touch::tick(millis());
        if (bootPressed()) { waitBootRelease(); return -1; }

        if (tft.getTouch(&tp, 1) > 0) {
            // Y axis is inverted on this panel
            int tapY = (LCD_HEIGHT - 1) - tp.y;
            Serial.printf("[BIOS] Touch raw y=%d → mapped y=%d\n", tp.y, tapY);

            // Wait for release
            while (tft.getTouch(&tp, 1) > 0) delay(15);
            delay(50);  // debounce after release

            if (tapY >= 0) return tapY;
        }

        delay(20);
    }
}

// ── List menu helper ──────────────────────────────────────
// Draws a simple tappable list and returns which item was tapped.
// Returns -1 for BOOT (back).

struct MenuDef {
    const char* title;
    const char** items;
    int count;
    int top;
    int itemH;
};

static void drawList(const MenuDef& m) {
    cls();
    drawCentered(m.title, 4, CYAN);
    tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);

    for (int i = 0; i < m.count; i++) {
        int y = m.top + i * m.itemH;
        tft.drawFastHLine(10, y + m.itemH - 1, LCD_WIDTH - 20, 0x2104);
        drawLeft(m.items[i], 16, y + 5, WHITE);
    }
    drawSmall("BOOT = back", 300, DIM);
}

static int menuLoop(const MenuDef& m) {
    drawList(m);
    for (;;) {
        int tapY = waitTapY();
        if (tapY < 0) return -1;  // BOOT

        int idx = (tapY - m.top) / m.itemH;
        if (idx < 0 || idx >= m.count) continue;

        // Flash item
        int fy = m.top + idx * m.itemH;
        tft.fillRect(8, fy, LCD_WIDTH - 16, m.itemH - 1, 0x0A2A);
        drawLeft(m.items[idx], 16, fy + 5, CYAN);
        delay(100);

        return idx;
    }
}

// ── Sub-screen: Audio Test ────────────────────────────────

static void audioTestScreen() {
    const char* items[] = { "Beep Tone", "Mic Level", "Echo Test", "Back" };
    MenuDef menu = { "Audio Test", items, 4, 30, 28 };

    for (;;) {
        int sel = menuLoop(menu);
        if (sel < 0 || sel == 3) return;  // BOOT or Back

        if (sel == 0) {
            cls();
            drawSmall("Playing 800Hz...", 140, WHITE);
            int16_t buf[320];
            for (int off = 0; off < 16000; off += 320) {
                int n = min(320, 16000 - off);
                for (int i = 0; i < n; i++) {
                    float t = (float)(off + i) / 16000.0f;
                    buf[i] = (int16_t)(16000.0f * sinf(2.0f * PI * 800.0f * t));
                }
                audio_io::writeSpeaker(buf, n);
            }
            drawSmall("Done!", 165, GREEN);
            delay(400);
        }
        else if (sel == 1) {
            cls();
            drawSmall("Mic Level", 4, CYAN);
            drawSmall("Tap or BOOT to stop", 24, DIM);
            const int barX = 20, barY = 130, barW = LCD_WIDTH - 40, barH = 16;
            tft.drawRect(barX - 1, barY - 1, barW + 2, barH + 2, DIM);

            lgfx::touch_point_t tp2;
            int16_t micBuf[320];
            while (tft.getTouch(&tp2, 1) == 0 && !bootPressed()) {
                size_t samples = audio_io::readMic(micBuf, 320);
                if (samples > 0) {
                    int64_t sum = 0;
                    for (size_t i = 0; i < samples; i++)
                        sum += (int64_t)micBuf[i] * micBuf[i];
                    float level = sqrtf((float)(sum / (int64_t)samples)) / 32768.0f;
                    if (level > 1.0f) level = 1.0f;
                    int fillW = (int)(level * barW);
                    uint16_t col = (level > 0.8f) ? RED : (level > 0.4f) ? YELLOW : GREEN;
                    tft.fillRect(barX, barY, fillW, barH, col);
                    if (fillW < barW) tft.fillRect(barX + fillW, barY, barW - fillW, barH, BG);
                    char db[16];
                    snprintf(db, sizeof(db), "%.0f dB", 20.0f * log10f(level + 0.0001f));
                    tft.fillRect(CX - 30, 155, 60, 18, BG);
                    drawSmall(db, 155, WHITE);
                }
            }
            while (tft.getTouch(&tp2, 1) > 0) delay(15);
            if (bootPressed()) waitBootRelease();
        }
        else if (sel == 2) {
            cls();
            drawSmall("Echo Test", 4, CYAN);
            drawSmall("Speak — you'll hear yourself", 120, WHITE);
            drawSmall("Tap or BOOT to stop", 145, DIM);

            lgfx::touch_point_t tp3;
            int16_t echoBuf[320];
            while (tft.getTouch(&tp3, 1) == 0 && !bootPressed()) {
                size_t samples = audio_io::readMic(echoBuf, 320);
                if (samples > 0) audio_io::writeSpeaker(echoBuf, samples);
            }
            while (tft.getTouch(&tp3, 1) > 0) delay(15);
            if (bootPressed()) waitBootRelease();
        }
    }
}

// ── Sub-screen: WiFi Scan ─────────────────────────────────

static void wifiScanScreen() {
    cls();
    drawSmall("Scanning WiFi...", 140, WHITE);

    WiFi.mode(WIFI_STA);
    int n = WiFi.scanNetworks();

    cls();
    drawCentered("WiFi Scan", 4, CYAN);
    tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);

    if (n <= 0) {
        drawSmall("No networks found", 140, RED);
        drawSmall("Tap or BOOT to go back", 165, DIM);
        waitTapY();
        WiFi.scanDelete();
        return;
    }

    int page = 0;
    const int perPage = 10;
    int totalPages = (n + perPage - 1) / perPage;

    auto draw = [&]() {
        tft.fillRect(0, 28, LCD_WIDTH, 262, BG);
        char hdr[32];
        snprintf(hdr, sizeof(hdr), "%d networks", n);
        drawSmall(hdr, 28, DIM);

        int start = page * perPage;
        int end = start + perPage;
        if (end > n) end = n;

        for (int i = start; i < end; i++) {
            int y = 46 + (i - start) * 22;
            int rssi = WiFi.RSSI(i);
            int bars = (rssi > -50) ? 4 : (rssi > -60) ? 3 : (rssi > -70) ? 2 : 1;

            for (int b = 0; b < 4; b++) {
                int bx = LCD_WIDTH - 32 + b * 6;
                int bh = 3 + b * 3;
                tft.fillRect(bx, y + 14 - bh, 4, bh, (b < bars) ? GREEN : 0x4208);
            }

            char ssidStr[22];
            String ssid = WiFi.SSID(i);
            if (ssid.length() > 18) {
                snprintf(ssidStr, sizeof(ssidStr), "%.15s...", ssid.c_str());
            } else {
                strncpy(ssidStr, ssid.c_str(), sizeof(ssidStr) - 1);
                ssidStr[sizeof(ssidStr) - 1] = '\0';
            }
            if (WiFi.encryptionType(i) != WIFI_AUTH_OPEN)
                drawLeft("*", 8, y, YELLOW);
            drawLeft(ssidStr, 16, y, WHITE);
        }

        if (totalPages > 1) {
            char pg[8];
            snprintf(pg, sizeof(pg), "%d/%d", page + 1, totalPages);
            drawSmall(pg, 275, DIM);
        }
        drawSmall("Tap:next page  BOOT:back", 295, DIM);
    };

    draw();
    for (;;) {
        int tapY = waitTapY();
        if (tapY < 0) break;  // BOOT
        page = (page + 1) % totalPages;
        draw();
    }
    WiFi.scanDelete();
}

// ── Sub-screen: System Info ───────────────────────────────

static void systemInfoScreen() {
    cls();
    drawCentered("System Info", 4, CYAN);
    tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);

    int y = 32;
    const int lineH = 20;

    auto line = [&](const char* label, const char* value) {
        drawLeft(label, 10, y, DIM);
        drawRight(value, LCD_WIDTH - 10, y, WHITE);
        y += lineH;
    };

    esp_chip_info_t chip;
    esp_chip_info(&chip);

    char buf[40];
    snprintf(buf, sizeof(buf), "ESP32-S3 r%d", chip.revision);
    line("Chip", buf);

    snprintf(buf, sizeof(buf), "%d cores @ %luMHz", chip.cores, ESP.getCpuFreqMHz());
    line("CPU", buf);

    snprintf(buf, sizeof(buf), "%luMB", ESP.getFlashChipSize() / (1024 * 1024));
    line("Flash", buf);

    snprintf(buf, sizeof(buf), "%u/%uKB",
             (unsigned)(ESP.getFreePsram() / 1024), (unsigned)(ESP.getPsramSize() / 1024));
    line("PSRAM free", buf);

    snprintf(buf, sizeof(buf), "%uKB", (unsigned)(ESP.getFreeHeap() / 1024));
    line("Heap free", buf);

    uint8_t mac[6];
    WiFi.macAddress(mac);
    snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    line("MAC", buf);

    line("Firmware", FIRMWARE_VERSION);
    line("Display", "ILI9341V 240x320");

    snprintf(buf, sizeof(buf), "%lus", (unsigned long)(millis() / 1000));
    line("Uptime", buf);

    drawSmall("Tap or BOOT to go back", 295, DIM);
    waitTapY();
}

// ── Sub-screen: Factory Reset ─────────────────────────────

static void factoryResetScreen() {
    const char* items[] = { "Yes, erase everything", "No, go back" };
    MenuDef menu = { "Factory Reset?", items, 2, 50, 32 };

    cls();
    drawCentered("Factory Reset?", 4, RED);
    tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);
    drawSmall("This will erase WiFi,", 30, WHITE);
    drawSmall("device token, and all settings.", 46, WHITE);

    for (int i = 0; i < 2; i++) {
        int y = 80 + i * 32;
        tft.drawFastHLine(10, y + 31, LCD_WIDTH - 20, 0x2104);
        uint16_t col = (i == 0) ? RED : GREEN;
        drawLeft(items[i], 16, y + 7, col);
    }
    drawSmall("BOOT = cancel", 300, DIM);

    for (;;) {
        int tapY = waitTapY();
        if (tapY < 0) return;  // BOOT = cancel

        int idx = (tapY - 80) / 32;
        if (idx == 0) {
            // Confirmed — erase and reboot
            cls();
            drawSmall("Erasing...", 140, RED);
            nvs_store::eraseAll();
            delay(500);
            drawSmall("Done! Rebooting...", 165, GREEN);
            delay(1000);
            ESP.restart();
        }
        if (idx == 1) return;  // Cancel
    }
}

// ── Status dashboard (drawn at top of BIOS main menu) ────

static void drawStatusDashboard() {
    // Status area: y 30-105
    int y = 30;
    const int lineH = 16;
    const int valX = LCD_WIDTH - 12;

    auto statusLine = [&](const char* label, const char* value, uint16_t valColor) {
        drawLeft(label, 12, y, DIM);
        drawRight(value, valX, y, valColor);
        y += lineH;
    };

    // WiFi
    if (WiFi.isConnected()) {
        int rssi = WiFi.RSSI();
        char rssiStr[16];
        snprintf(rssiStr, sizeof(rssiStr), "%d dBm", rssi);
        uint16_t col = (rssi > -50) ? GREEN : (rssi > -70) ? YELLOW : RED;
        statusLine("WiFi", rssiStr, col);

        char ipStr[20];
        snprintf(ipStr, sizeof(ipStr), "%s", WiFi.localIP().toString().c_str());
        statusLine("IP", ipStr, WHITE);
    } else {
        statusLine("WiFi", "Disconnected", RED);
    }

    // Backend
    statusLine("Backend", appState.wsConnected ? "Online" : "Offline",
               appState.wsConnected ? GREEN : RED);

    // Battery
    // TODO: Read GPIO9 ADC for actual battery level
    statusLine("Power", "USB", GREEN);

    // SD card
    statusLine("SD Card", sd_storage::isMounted() ? "Mounted" : "No card",
               sd_storage::isMounted() ? GREEN : YELLOW);

    // Separator
    tft.drawFastHLine(10, y + 2, LCD_WIDTH - 20, DIM);
}

// ── Main BIOS menu ────────────────────────────────────────

bool bios_menu::show() {
    // Wait for any residual touch to clear (finger still on screen from BOOT press)
    lgfx::touch_point_t tp0;
    while (tft.getTouch(&tp0, 1) > 0) delay(15);
    delay(100);

    const char* items[] = { "Continue Boot", "Audio Test", "WiFi Scan", "System Info", "Setup WiFi", "Factory Reset" };
    const int statusAreaEnd = 115;  // Status dashboard takes y 30-110
    MenuDef menu = { "BIOS", items, 6, statusAreaEnd, 28 };

    for (;;) {
        // Draw menu with status dashboard
        cls();
        drawCentered(menu.title, 4, CYAN);
        tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);
        drawStatusDashboard();

        for (int i = 0; i < menu.count; i++) {
            int iy = menu.top + i * menu.itemH;
            tft.drawFastHLine(10, iy + menu.itemH - 1, LCD_WIDTH - 20, 0x2104);
            drawLeft(menu.items[i], 16, iy + 5, WHITE);
        }
        drawSmall("BOOT = back", 300, DIM);

        // Wait for selection
        int tapY = waitTapY();
        if (tapY < 0) continue;  // BOOT in main menu = no-op

        int idx = (tapY - menu.top) / menu.itemH;
        if (idx < 0 || idx >= menu.count) continue;

        // Flash item
        int fy = menu.top + idx * menu.itemH;
        tft.fillRect(8, fy, LCD_WIDTH - 16, menu.itemH - 1, 0x0A2A);
        drawLeft(menu.items[idx], 16, fy + 5, CYAN);
        delay(100);

        switch (idx) {
            case 0: return false;              // Continue Boot
            case 1: audioTestScreen(); break;
            case 2: wifiScanScreen(); break;
            case 3: systemInfoScreen(); break;
            case 4: return true;               // Setup WiFi
            case 5: factoryResetScreen(); break;
        }
    }
}
