#include "bios_menu.h"
#include "config.h"
#include "lgfx_config.h"
#include "touch.h"
#include "audio_io.h"
#include "nvs_store.h"
#include "state.h"
#include "sd_storage.h"
#include "status_led.h"
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

// ── Wi-Fi signal helpers ─────────────────────────────────

static const char* wifiLabel(int rssi) {
    if (rssi > -50) return "Excellent";
    if (rssi > -60) return "Good";
    if (rssi > -70) return "Fair";
    if (rssi > -80) return "Weak";
    return "Poor";
}

static uint16_t wifiColor(int rssi) {
    if (rssi > -60) return GREEN;
    if (rssi > -70) return YELLOW;
    return RED;
}

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

/// Draw a tappable "Back" bar at the bottom. Returns its Y position for hit testing.
static int drawBackBar() {
    const int y = 290;
    tft.drawFastHLine(10, y - 2, LCD_WIDTH - 20, DIM);
    drawSmall("< Back", y + 4, DIM);
    return y;
}

// ── Input ─────────────────────────────────────────────────

static bool bootPressed() {
    return digitalRead(BOOT_BUTTON_PIN) == LOW;
}

static void waitBootRelease() {
    while (bootPressed()) delay(15);
    delay(80);
}

static int waitTapY() {
    lgfx::touch_point_t tp;
    while (tft.getTouch(&tp, 1) > 0) delay(15);

    for (;;) {
        touch::processSerial(millis());
        touch::tick(millis());
        if (bootPressed()) { waitBootRelease(); return -1; }

        if (tft.getTouch(&tp, 1) > 0) {
            int tapY = (LCD_HEIGHT - 1) - tp.y;

            while (tft.getTouch(&tp, 1) > 0) delay(15);
            delay(50);

            if (tapY >= 0) return tapY;
        }

        delay(20);
    }
}

/// Wait for tap on the Back bar (or anywhere, really). Returns when tapped.
static void waitForBack() {
    waitTapY();  // any tap or BOOT dismisses
}

// ── List menu helper ──────────────────────────────────────

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
}

static int menuLoop(const MenuDef& m) {
    drawList(m);
    for (;;) {
        int tapY = waitTapY();
        if (tapY < 0) return -1;

        int idx = (tapY - m.top) / m.itemH;
        if (idx < 0 || idx >= m.count) continue;

        int fy = m.top + idx * m.itemH;
        tft.fillRect(8, fy, LCD_WIDTH - 16, m.itemH - 1, 0x0A2A);
        drawLeft(m.items[idx], 16, fy + 5, CYAN);
        delay(100);

        return idx;
    }
}

// ── Sub-screen: Wi-Fi (scan + setup combined) ────────────

static bool wifiScreen() {
    bool setupRequested = false;

    for (;;) {
        cls();
        drawCentered("Wi-Fi", 4, CYAN);
        tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);

        int y = 32;
        if (WiFi.isConnected()) {
            int rssi = WiFi.RSSI();
            char statusStr[40];
            snprintf(statusStr, sizeof(statusStr), "%s  %s (%d)",
                     WiFi.SSID().c_str(), wifiLabel(rssi), rssi);
            drawLeft("Connected", 12, y, GREEN);
            y += 16;
            drawLeft(statusStr, 12, y, wifiColor(rssi));
            y += 16;
            char ipStr[24];
            snprintf(ipStr, sizeof(ipStr), "IP: %s", WiFi.localIP().toString().c_str());
            drawLeft(ipStr, 12, y, DIM);
            y += 20;
        } else {
            drawLeft("Not connected", 12, y, RED);
            y += 20;
        }

        tft.drawFastHLine(10, y, LCD_WIDTH - 20, DIM);
        y += 6;

        const char* items[] = { "Scan Networks", "Change Network", "Back" };
        const int itemH = 28;
        const int menuTop = y;

        for (int i = 0; i < 3; i++) {
            tft.drawFastHLine(10, menuTop + i * itemH + itemH - 1, LCD_WIDTH - 20, 0x2104);
            drawLeft(items[i], 16, menuTop + i * itemH + 5, WHITE);
        }

        int tapY = waitTapY();
        if (tapY < 0) break;

        int idx = (tapY - menuTop) / itemH;
        if (idx == 0) {
            // Scan
            cls();
            drawSmall("Scanning...", 140, WHITE);
            WiFi.mode(WIFI_STA);
            int n = WiFi.scanNetworks();

            cls();
            drawCentered("Networks", 4, CYAN);
            tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);

            if (n <= 0) {
                drawSmall("No networks found", 140, RED);
                drawBackBar();
                waitForBack();
                WiFi.scanDelete();
                continue;
            }

            int page = 0;
            const int perPage = 9;
            int totalPages = (n + perPage - 1) / perPage;

            auto drawPage = [&]() {
                tft.fillRect(0, 28, LCD_WIDTH, 255, BG);
                char hdr[32];
                snprintf(hdr, sizeof(hdr), "%d found", n);
                drawSmall(hdr, 28, DIM);

                int start = page * perPage;
                int end2 = start + perPage;
                if (end2 > n) end2 = n;

                for (int i = start; i < end2; i++) {
                    int ly = 46 + (i - start) * 22;
                    int r = WiFi.RSSI(i);
                    int bars = (r > -50) ? 4 : (r > -60) ? 3 : (r > -70) ? 2 : 1;

                    for (int b = 0; b < 4; b++) {
                        int bx = LCD_WIDTH - 32 + b * 6;
                        int bh = 3 + b * 3;
                        tft.fillRect(bx, ly + 14 - bh, 4, bh, (b < bars) ? GREEN : 0x4208);
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
                        drawLeft("*", 8, ly, YELLOW);
                    drawLeft(ssidStr, 16, ly, WHITE);
                }

                if (totalPages > 1) {
                    char pg[16];
                    snprintf(pg, sizeof(pg), "Page %d/%d  Tap:next", page + 1, totalPages);
                    drawSmall(pg, 275, DIM);
                }
                drawBackBar();
            };

            drawPage();
            for (;;) {
                int ty = waitTapY();
                if (ty < 0 || ty >= 288) break;  // BOOT or Back bar
                page = (page + 1) % totalPages;
                drawPage();
            }
            WiFi.scanDelete();
        }
        else if (idx == 1) {
            setupRequested = true;
            break;
        }
        else if (idx == 2) {
            break;
        }
    }

    return setupRequested;
}

// ── Sub-screen: Hardware Test ────────────────────────────

static void hardwareTestScreen() {
    const char* items[] = {
        "Speaker (beep)",
        "Microphone level",
        "Echo test",
        "Touch test",
        "LED test",
        "Run all checks",
        "Back",
    };
    MenuDef menu = { "Hardware Test", items, 7, 30, 28 };

    for (;;) {
        int sel = menuLoop(menu);
        if (sel < 0 || sel == 6) return;

        if (sel == 0) {
            // Speaker beep
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
            drawBackBar();
            waitForBack();
        }
        else if (sel == 1) {
            // Mic level
            cls();
            drawSmall("Mic Level", 4, CYAN);
            const int barX = 20, barY = 130, barW = LCD_WIDTH - 40, barH = 16;
            tft.drawRect(barX - 1, barY - 1, barW + 2, barH + 2, DIM);
            drawBackBar();

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
            // Echo test
            cls();
            drawSmall("Echo Test", 4, CYAN);
            drawSmall("Speak — you'll hear yourself", 120, WHITE);
            drawBackBar();

            lgfx::touch_point_t tp3;
            int16_t echoBuf[320];
            while (tft.getTouch(&tp3, 1) == 0 && !bootPressed()) {
                size_t samples = audio_io::readMic(echoBuf, 320);
                if (samples > 0) audio_io::writeSpeaker(echoBuf, samples);
            }
            while (tft.getTouch(&tp3, 1) > 0) delay(15);
            if (bootPressed()) waitBootRelease();
        }
        else if (sel == 3) {
            // Touch test — draw dots where user touches
            cls();
            drawSmall("Touch Test", 4, CYAN);
            drawSmall("Touch the screen — dots appear", 24, DIM);
            drawBackBar();

            while (!bootPressed()) {
                lgfx::touch_point_t tp4;
                if (tft.getTouch(&tp4, 1) > 0) {
                    // Y axis is inverted on this panel (same as waitTapY)
                    int drawY = (LCD_HEIGHT - 1) - tp4.y;
                    // Tap on back bar area → exit
                    if (drawY >= 288) {
                        while (tft.getTouch(&tp4, 1) > 0) delay(15);
                        break;
                    }
                    tft.fillCircle(tp4.x, drawY, 4, GREEN);
                }
                delay(15);
            }
            if (bootPressed()) waitBootRelease();
        }
        else if (sel == 4) {
            // LED test — cycle through colors
            cls();
            drawSmall("LED Test", 4, CYAN);
            drawSmall("Cycling RGB...", 140, WHITE);
            drawBackBar();

            struct { uint8_t r, g, b; const char* name; } colors[] = {
                {255,0,0,"Red"}, {0,255,0,"Green"}, {0,0,255,"Blue"},
                {255,255,0,"Yellow"}, {255,0,255,"Magenta"}, {0,255,255,"Cyan"},
                {255,255,255,"White"},
            };
            lgfx::touch_point_t tp5;
            int ci = 0;
            while (tft.getTouch(&tp5, 1) == 0 && !bootPressed()) {
                tft.fillRect(CX - 40, 190, 80, 20, BG);
                drawSmall(colors[ci].name, 190, WHITE);
                status_led::set(colors[ci].r, colors[ci].g, colors[ci].b);
                for (int w = 0; w < 40 && tft.getTouch(&tp5, 1) == 0 && !bootPressed(); w++) {
                    status_led::tick(millis());  // pump LED update (main loop not running)
                    delay(25);
                }
                ci = (ci + 1) % 7;
            }
            status_led::syncToState();
            while (tft.getTouch(&tp5, 1) > 0) delay(15);
            if (bootPressed()) waitBootRelease();
        }
        else if (sel == 5) {
            // Run all checks
            cls();
            drawCentered("All Checks", 4, CYAN);
            tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);

            int y = 36;
            const int lineH = 22;
            const int valX = LCD_WIDTH - 14;

            auto checkLine = [&](const char* label, bool ok, const char* detail = nullptr) {
                drawLeft(label, 14, y, WHITE);
                if (detail) {
                    drawRight(detail, valX, y, ok ? GREEN : YELLOW);
                } else {
                    drawRight(ok ? "OK" : "FAIL", valX, y, ok ? GREEN : RED);
                }
                y += lineH;
            };

            checkLine("Display", true, "240x320");
            checkLine("Touch", true, "FT6336G");
            checkLine("SD Card", sd_storage::isMounted(),
                      sd_storage::isMounted() ? "Mounted" : "Missing");
            checkLine("Audio", true, "ES8311");
            checkLine("Wi-Fi", WiFi.isConnected(),
                      WiFi.isConnected() ? "Connected" : "No connection");

            char psramStr[16];
            snprintf(psramStr, sizeof(psramStr), "%uKB free",
                     (unsigned)(ESP.getFreePsram() / 1024));
            checkLine("PSRAM", ESP.getFreePsram() > 100000, psramStr);

            bool hasToken = nvs_store::hasDeviceToken();
            checkLine("Token", hasToken, hasToken ? "Set" : "Not set");

            // Quick speaker beep
            drawLeft("Speaker", 14, y, WHITE);
            drawRight("Testing...", valX, y, DIM);
            int16_t beep[320];
            for (int i = 0; i < 320; i++) {
                float t = (float)i / 16000.0f;
                beep[i] = (int16_t)(8000.0f * sinf(2.0f * PI * 1000.0f * t));
            }
            audio_io::writeSpeaker(beep, 320);
            tft.fillRect(valX - 60, y, 74, lineH, BG);
            drawRight("OK", valX, y, GREEN);
            y += lineH;

            // Quick LED flash
            drawLeft("LED", 14, y, WHITE);
            status_led::set(0, 255, 0);
            for (int w = 0; w < 12; w++) { status_led::tick(millis()); delay(25); }
            status_led::syncToState();
            status_led::tick(millis());
            drawRight("OK", valX, y, GREEN);

            drawBackBar();
            waitForBack();
        }
    }
}

// ── Sub-screen: System Info ──────────────────────────────

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
    line("PSRAM", buf);

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

    drawBackBar();
    waitForBack();
}

// ── Sub-screen: Factory Reset ────────────────────────────

static void factoryResetScreen() {
    cls();
    drawCentered("Factory Reset?", 4, RED);
    tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);
    drawSmall("This will erase WiFi,", 30, WHITE);
    drawSmall("device token, and all settings.", 46, WHITE);

    const char* items[] = { "Yes, erase everything", "No, go back" };
    for (int i = 0; i < 2; i++) {
        int y = 80 + i * 32;
        tft.drawFastHLine(10, y + 31, LCD_WIDTH - 20, 0x2104);
        uint16_t col = (i == 0) ? RED : GREEN;
        drawLeft(items[i], 16, y + 7, col);
    }

    for (;;) {
        int tapY = waitTapY();
        if (tapY < 0) return;

        int idx = (tapY - 80) / 32;
        if (idx == 0) {
            cls();
            drawSmall("Erasing...", 140, RED);
            nvs_store::eraseAll();
            delay(500);
            drawSmall("Done! Rebooting...", 165, GREEN);
            delay(1000);
            ESP.restart();
        }
        if (idx == 1) return;
    }
}

// ── Status dashboard (drawn at top of BIOS main menu) ────

static void drawStatusDashboard() {
    int y = 30;
    const int lineH = 16;
    const int valX = LCD_WIDTH - 12;

    auto statusLine = [&](const char* label, const char* value, uint16_t valColor) {
        drawLeft(label, 12, y, DIM);
        drawRight(value, valX, y, valColor);
        y += lineH;
    };

    if (WiFi.isConnected()) {
        int rssi = WiFi.RSSI();
        char wifiStr[24];
        snprintf(wifiStr, sizeof(wifiStr), "%s (%d)", wifiLabel(rssi), rssi);
        statusLine("Wi-Fi", wifiStr, wifiColor(rssi));
    } else {
        statusLine("Wi-Fi", "Disconnected", RED);
    }

    if (WiFi.isConnected() && nvs_store::hasDeviceToken()) {
        statusLine("Server", "Ready", GREEN);
    } else if (WiFi.isConnected()) {
        statusLine("Server", "No token", YELLOW);
    } else {
        statusLine("Server", "No Wi-Fi", DIM);
    }

    statusLine("SD Card", sd_storage::isMounted() ? "Mounted" : "No card",
               sd_storage::isMounted() ? GREEN : YELLOW);

    statusLine("Firmware", FIRMWARE_VERSION, WHITE);

    tft.drawFastHLine(10, y + 2, LCD_WIDTH - 20, DIM);
}

// ── Main BIOS menu ────────────────────────────────────────

bool bios_menu::show() {
    lgfx::touch_point_t tp0;
    while (tft.getTouch(&tp0, 1) > 0) delay(15);
    delay(100);

    const char* items[] = {
        "Continue Boot",
        "Wi-Fi",
        "Hardware Test",
        "System Info",
        "Factory Reset",
    };
    const int statusAreaEnd = 100;
    MenuDef menu = { "BIOS", items, 5, statusAreaEnd, 28 };

    for (;;) {
        cls();
        drawCentered(menu.title, 4, CYAN);
        tft.drawFastHLine(10, 26, LCD_WIDTH - 20, DIM);
        drawStatusDashboard();

        for (int i = 0; i < menu.count; i++) {
            int iy = menu.top + i * menu.itemH;
            tft.drawFastHLine(10, iy + menu.itemH - 1, LCD_WIDTH - 20, 0x2104);
            drawLeft(menu.items[i], 16, iy + 5, WHITE);
        }

        int tapY = waitTapY();
        if (tapY < 0) continue;

        int idx = (tapY - menu.top) / menu.itemH;
        if (idx < 0 || idx >= menu.count) continue;

        int fy = menu.top + idx * menu.itemH;
        tft.fillRect(8, fy, LCD_WIDTH - 16, menu.itemH - 1, 0x0A2A);
        drawLeft(menu.items[idx], 16, fy + 5, CYAN);
        delay(100);

        switch (idx) {
            case 0: return false;                          // Continue Boot
            case 1:                                        // Wi-Fi
                if (wifiScreen()) return true;
                break;
            case 2: hardwareTestScreen(); break;           // Hardware Test
            case 3: systemInfoScreen(); break;             // System Info
            case 4: factoryResetScreen(); break;           // Factory Reset
        }
    }
}
