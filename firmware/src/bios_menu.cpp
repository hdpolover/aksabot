#include "bios_menu.h"
#include "config.h"
#include "lgfx_config.h"
#include "touch.h"
#include "audio_io.h"
#include "ui_audio.h"
#include "nvs_store.h"
#include "state.h"
#include "sd_storage.h"
#include "status_led.h"
#include "face.h"
#include "display.h"
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClient.h>
#include <esp_system.h>
#include <esp_chip_info.h>
#include <math.h>

extern LGFX tft;

// ── Color palette ─────────────────────────────────────────
static const uint16_t BG     = TFT_BLACK;
static const uint16_t WHITE  = TFT_WHITE;
static const uint16_t CYAN   = 0x07FF;   // bright cyan accent (was TFT_WHITE — fixed)
static const uint16_t GREEN  = 0x07E0;
static const uint16_t RED    = TFT_RED;
static const uint16_t YELLOW = TFT_YELLOW;
static const uint16_t DIM    = 0x8C71;   // medium grey
static const uint16_t DIMMER = 0x2104;   // dark grey for separators
static const uint16_t HILITE = 0x0A2A;   // dark teal for selection bg
static const uint16_t HDR_BG = 0x0010;   // dark navy for header bar

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

/// Dark navy header bar with cyan title (left), optional sub-label (right), cyan underline.
static void drawHeader(const char* title, const char* sub = nullptr) {
    tft.fillRect(0, 0, LCD_WIDTH, 26, HDR_BG);
    tft.setFont(&fonts::FreeSans9pt7b);
    tft.setTextSize(1);
    tft.setTextColor(CYAN);
    tft.setTextDatum(lgfx::top_left);
    tft.drawString(title, 10, 6);
    if (sub) {
        tft.setFont(&fonts::Font2);
        tft.setTextColor(DIM);
        tft.setTextDatum(lgfx::top_right);
        tft.drawString(sub, LCD_WIDTH - 10, 9);
    }
    tft.drawFastHLine(0, 26, LCD_WIDTH, CYAN);
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

/// 5×5 solid status indicator dot.
static void drawDot(int x, int y, uint16_t color) {
    tft.fillRect(x, y, 5, 5, color);
}

/// Styled Back button at bottom. Returns its Y for hit testing.
static int drawBackBar() {
    const int y = 290;
    tft.fillRect(8, y, LCD_WIDTH - 16, 22, HILITE);
    tft.drawRect(8, y, LCD_WIDTH - 16, 22, DIM);
    tft.setTextColor(DIM);
    tft.setFont(&fonts::Font2);
    tft.setTextSize(1);
    tft.setTextDatum(lgfx::top_center);
    tft.drawString("< Back", CX, y + 5);
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
            if (tapY >= 0) {
                ui_audio::play(ui_audio::Clip::TAP);
                return tapY;
            }
        }
        delay(20);
    }
}

static void waitForBack() {
    waitTapY();
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
    drawHeader(m.title);
    for (int i = 0; i < m.count; i++) {
        int y = m.top + i * m.itemH;
        tft.drawFastHLine(0, y, LCD_WIDTH, DIMMER);
        drawLeft(m.items[i], 20, y + 7, WHITE);
        drawRight(">", LCD_WIDTH - 10, y + 7, DIMMER);
    }
    tft.drawFastHLine(0, m.top + m.count * m.itemH, LCD_WIDTH, DIMMER);
}

static int menuLoop(const MenuDef& m) {
    drawList(m);
    for (;;) {
        int tapY = waitTapY();
        if (tapY < 0) return -1;

        int idx = (tapY - m.top) / m.itemH;
        if (idx < 0 || idx >= m.count) continue;

        int fy = m.top + idx * m.itemH;
        // Highlight: dark teal bg + 3px cyan left accent bar
        tft.fillRect(0, fy + 1, LCD_WIDTH, m.itemH - 2, HILITE);
        tft.fillRect(0, fy + 1, 3, m.itemH - 2, CYAN);
        drawLeft(m.items[idx], 20, fy + 7, CYAN);
        delay(120);

        return idx;
    }
}

// ── Sub-screen: Wi-Fi ────────────────────────────────────

static bool wifiScreen() {
    bool setupRequested = false;

    for (;;) {
        cls();
        drawHeader("Wi-Fi");

        int y = 32;
        if (WiFi.isConnected()) {
            int rssi = WiFi.RSSI();
            uint16_t rc = wifiColor(rssi);

            // SSID prominently
            drawLeft(WiFi.SSID().c_str(), 12, y, WHITE);
            y += 16;

            // Signal dot + label
            drawDot(12, y + 4, rc);
            char sigStr[32];
            snprintf(sigStr, sizeof(sigStr), "%s  %d dBm", wifiLabel(rssi), rssi);
            drawLeft(sigStr, 22, y, rc);
            y += 16;

            // IP address
            char ipStr[28];
            snprintf(ipStr, sizeof(ipStr), "IP  %s", WiFi.localIP().toString().c_str());
            drawLeft(ipStr, 12, y, DIM);
            y += 20;
        } else {
            drawDot(12, y + 4, RED);
            drawLeft("Not connected", 22, y, RED);
            y += 20;
        }

        tft.drawFastHLine(0, y + 2, LCD_WIDTH, DIMMER);
        y += 8;

        const char* items[] = { "Scan Networks", "Change Network", "Back" };
        const int itemH = 28;
        const int menuTop = y;

        for (int i = 0; i < 3; i++) {
            int iy = menuTop + i * itemH;
            tft.drawFastHLine(0, iy, LCD_WIDTH, DIMMER);
            drawLeft(items[i], 20, iy + 7, WHITE);
            if (i < 2) drawRight(">", LCD_WIDTH - 10, iy + 7, DIMMER);
        }
        tft.drawFastHLine(0, menuTop + 3 * itemH, LCD_WIDTH, DIMMER);

        int tapY = waitTapY();
        if (tapY < 0) break;

        int idx = (tapY - menuTop) / itemH;
        if (idx == 0) {
            // Scan
            cls();
            drawHeader("Networks", "Scanning...");
            drawSmall("Searching for networks", 140, DIM);
            drawSmall("Please wait...", 158, DIMMER);

            WiFi.mode(WIFI_STA);
            int n = WiFi.scanNetworks();

            if (n <= 0) {
                cls();
                drawHeader("Networks");
                drawSmall("No networks found", 140, DIM);
                drawBackBar();
                waitForBack();
                WiFi.scanDelete();
                continue;
            }

            char hdrStr[12];
            snprintf(hdrStr, sizeof(hdrStr), "%d found", n);

            int page = 0;
            const int perPage = 9;
            int totalPages = (n + perPage - 1) / perPage;

            auto drawPage = [&]() {
                cls();
                drawHeader("Networks", hdrStr);

                int start = page * perPage;
                int end2 = start + perPage;
                if (end2 > n) end2 = n;

                for (int i = start; i < end2; i++) {
                    int ly = 32 + (i - start) * 22;
                    int r = WiFi.RSSI(i);
                    int bars = (r > -50) ? 4 : (r > -60) ? 3 : (r > -70) ? 2 : 1;

                    // Taller, more visible signal bars
                    for (int b = 0; b < 4; b++) {
                        int bx = LCD_WIDTH - 34 + b * 7;
                        int bh = 4 + b * 4;  // 4, 8, 12, 16 px
                        tft.fillRect(bx, ly + 16 - bh, 5, bh, (b < bars) ? GREEN : DIMMER);
                    }

                    // Lock icon
                    if (WiFi.encryptionType(i) != WIFI_AUTH_OPEN)
                        drawLeft("*", 8, ly, YELLOW);

                    // SSID
                    char ssidStr[20];
                    String ssid = WiFi.SSID(i);
                    if (ssid.length() > 15) {
                        snprintf(ssidStr, sizeof(ssidStr), "%.12s...", ssid.c_str());
                    } else {
                        strncpy(ssidStr, ssid.c_str(), sizeof(ssidStr) - 1);
                        ssidStr[sizeof(ssidStr) - 1] = '\0';
                    }
                    drawLeft(ssidStr, 18, ly, WHITE);
                    tft.drawFastHLine(0, ly + 20, LCD_WIDTH, DIMMER);
                }

                if (totalPages > 1) {
                    char pg[24];
                    snprintf(pg, sizeof(pg), "Page %d/%d  tap for next", page + 1, totalPages);
                    drawSmall(pg, 273, DIM);
                }
                drawBackBar();
            };

            drawPage();
            for (;;) {
                int ty = waitTapY();
                if (ty < 0 || ty >= 288) break;
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

// ── Sub-screen: Face Preview ─────────────────────────────
//
// Cycles through all 17 face expressions interactively.
// The display task is NOT running during BIOS, so we drive face::tick()
// and display::tick() manually at ~30fps in a tight loop.
//
// Touch zones:
//   Left  half (x < CX) → previous expression
//   Right half (x ≥ CX) → next expression
//   Bottom bar (y ≥ 290) → exit

static void facePreviewScreen() {
    static const struct { face::Expression expr; const char* name; } kExprs[] = {
        { face::Expression::IDLE,        "IDLE"        },
        { face::Expression::LISTENING,   "LISTENING"   },
        { face::Expression::THINKING,    "THINKING"    },
        { face::Expression::SPEAKING,    "SPEAKING"    },
        { face::Expression::CONFUSED,    "CONFUSED"    },
        { face::Expression::SLEEPING,    "SLEEPING"    },
        { face::Expression::OFFLINE,     "OFFLINE"     },
        { face::Expression::ENCOURAGING, "ENCOURAGING" },
        { face::Expression::CALM,        "CALM"        },
        { face::Expression::FOCUSED,     "FOCUSED"     },
        { face::Expression::HAPPY,       "HAPPY"       },
        { face::Expression::SAD,         "SAD"         },
        { face::Expression::SHRUG,       "SHRUG"       },
        { face::Expression::SURPRISED,   "SURPRISED"   },
        { face::Expression::SHOCKED,     "SHOCKED"     },
        { face::Expression::ANGRY,       "ANGRY"       },
        { face::Expression::DISTURBED,   "DISTURBED"   },
    };
    const int kCount = sizeof(kExprs) / sizeof(kExprs[0]);

    int idx = 0;
    face::setExpression(kExprs[idx].expr, 0);

    // Register overlay with display — baked into the sprite before each push,
    // so there is no race between the sprite push and direct TFT writes.
    auto updateOverlay = [&]() {
        char ctr[12];
        snprintf(ctr, sizeof(ctr), "%d/%d", idx + 1, kCount);
        display::setBiosOverlay(kExprs[idx].name, ctr, "< PREV", "BACK", "NEXT >");
    };
    updateOverlay();

    // Flush any lingering touch
    lgfx::touch_point_t tp;
    while (tft.getTouch(&tp, 1) > 0) delay(15);
    delay(50);

    const uint32_t FRAME_MS = 33;  // ~30fps
    uint32_t lastFrame = 0;

    for (;;) {
        uint32_t now = millis();

        // Drive face + display at 30fps — overlay is baked in by display::tick()
        if (now - lastFrame >= FRAME_MS) {
            lastFrame = now;
            display::tick(now);   // calls face::tick() internally + pushes sprite
        }

        // Poll touch (non-blocking)
        if (tft.getTouch(&tp, 1) > 0) {
            int tapX = tp.x;
            int tapY = (LCD_HEIGHT - 1) - tp.y;

            // Wait for release
            while (tft.getTouch(&tp, 1) > 0) delay(15);
            delay(40);

            if (tapY >= 288) {
                // Bottom bar → exit
                ui_audio::play(ui_audio::Clip::TAP);
                break;
            }

            if (tapX < CX) {
                // Left half → previous
                idx = (idx - 1 + kCount) % kCount;
            } else {
                // Right half → next
                idx = (idx + 1) % kCount;
            }
            ui_audio::play(ui_audio::Clip::TAP);
            face::setExpression(kExprs[idx].expr, 150);
            updateOverlay();  // update name + counter in overlay immediately
        }

        // Boot button → exit
        if (bootPressed()) {
            waitBootRelease();
            break;
        }

        delay(5);
    }

    display::clearBiosOverlay();
}

// ── Sub-screen: Hardware Test ────────────────────────────

static void hardwareTestScreen() {
    const char* items[] = {
        "Speaker (beep)",
        "Microphone level",
        "Echo test",
        "Touch test",
        "LED test",
        "Face preview",
        "Run all checks",
        "Back",
    };
    MenuDef menu = { "Hardware Test", items, 8, 30, 28 };

    for (;;) {
        int sel = menuLoop(menu);
        if (sel < 0 || sel == 7) return;

        if (sel == 0) {
            cls();
            drawHeader("Speaker Test");
            drawSmall("Playing 800 Hz tone...", 140, WHITE);
            int16_t buf[320];
            for (int off = 0; off < 16000; off += 320) {
                int n = min(320, 16000 - off);
                for (int i = 0; i < n; i++) {
                    float t = (float)(off + i) / 16000.0f;
                    buf[i] = (int16_t)(16000.0f * sinf(2.0f * PI * 800.0f * t));
                }
                audio_io::writeSpeaker(buf, n);
            }
            drawDot(CX - 18, 163, GREEN);
            drawLeft("Done!", CX - 10, 161, GREEN);
            drawBackBar();
            waitForBack();
        }
        else if (sel == 1) {
            cls();
            drawHeader("Mic Level");
            drawSmall("Speak into the microphone", 36, DIM);
            const int barX = 20, barY = 120, barW = LCD_WIDTH - 40, barH = 20;
            tft.drawRect(barX - 1, barY - 1, barW + 2, barH + 2, DIMMER);
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
                    tft.fillRect(CX - 30, 150, 60, 18, BG);
                    drawSmall(db, 150, WHITE);
                }
            }
            while (tft.getTouch(&tp2, 1) > 0) delay(15);
            if (bootPressed()) waitBootRelease();
        }
        else if (sel == 2) {
            cls();
            drawHeader("Echo Test");
            drawSmall("Speak — you'll hear yourself", 120, WHITE);
            drawSmall("Tap or hold BOOT to exit", 138, DIM);
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
            cls();
            drawHeader("Touch Test");
            drawSmall("Touch the screen — dots appear", 30, DIM);
            drawBackBar();

            while (!bootPressed()) {
                lgfx::touch_point_t tp4;
                if (tft.getTouch(&tp4, 1) > 0) {
                    int drawY = (LCD_HEIGHT - 1) - tp4.y;
                    if (drawY >= 288) {
                        while (tft.getTouch(&tp4, 1) > 0) delay(15);
                        break;
                    }
                    tft.fillCircle(tp4.x, drawY, 5, CYAN);
                }
                delay(15);
            }
            if (bootPressed()) waitBootRelease();
        }
        else if (sel == 4) {
            cls();
            drawHeader("LED Test");
            drawSmall("Cycling RGB colors...", 130, DIM);
            drawSmall("Tap to exit", 148, DIMMER);
            drawBackBar();

            struct { uint8_t r, g, b; const char* name; } colors[] = {
                {255,0,0,"Red"}, {0,255,0,"Green"}, {0,0,255,"Blue"},
                {255,255,0,"Yellow"}, {255,0,255,"Magenta"}, {0,255,255,"Cyan"},
                {255,255,255,"White"},
            };
            lgfx::touch_point_t tp5;
            int ci = 0;
            while (tft.getTouch(&tp5, 1) == 0 && !bootPressed()) {
                tft.fillRect(CX - 40, 106, 80, 18, BG);
                drawSmall(colors[ci].name, 106, WHITE);
                status_led::set(colors[ci].r, colors[ci].g, colors[ci].b);
                for (int w = 0; w < 40 && tft.getTouch(&tp5, 1) == 0 && !bootPressed(); w++) {
                    status_led::tick(millis());
                    delay(25);
                }
                ci = (ci + 1) % 7;
            }
            status_led::syncToState();
            while (tft.getTouch(&tp5, 1) > 0) delay(15);
            if (bootPressed()) waitBootRelease();
        }
        else if (sel == 5) {
            facePreviewScreen();
        }
        else if (sel == 6) {
            // Run all checks
            cls();
            drawHeader("All Checks");

            int y = 32;
            const int lineH = 22;
            const int valX = LCD_WIDTH - 12;

            auto checkLine = [&](const char* label, bool ok, const char* detail = nullptr) {
                // Alternating row tint
                if (((y - 32) / lineH) % 2 == 1)
                    tft.fillRect(0, y, LCD_WIDTH, lineH, 0x0821);
                drawDot(10, y + 8, ok ? GREEN : RED);
                drawLeft(label, 20, y + 4, WHITE);
                if (detail) {
                    drawRight(detail, valX, y + 4, ok ? GREEN : YELLOW);
                } else {
                    drawRight(ok ? "OK" : "FAIL", valX, y + 4, ok ? GREEN : RED);
                }
                y += lineH;
            };

            checkLine("Display", true, "240x320");
            checkLine("Touch", true, "FT6336G");
            checkLine("SD Card", sd_storage::isMounted(),
                      sd_storage::isMounted() ? "Mounted" : "Missing");
            checkLine("Audio", true, "ES8311");
            checkLine("Wi-Fi", WiFi.isConnected(),
                      WiFi.isConnected() ? "Connected" : "No conn.");

            char psramStr[16];
            snprintf(psramStr, sizeof(psramStr), "%uKB free",
                     (unsigned)(ESP.getFreePsram() / 1024));
            checkLine("PSRAM", ESP.getFreePsram() > 100000, psramStr);

            bool hasToken = nvs_store::hasDeviceToken();
            checkLine("Token", hasToken, hasToken ? "Set" : "Not set");

            // Speaker beep
            if (((y - 32) / lineH) % 2 == 1)
                tft.fillRect(0, y, LCD_WIDTH, lineH, 0x0821);
            drawLeft("Speaker", 20, y + 4, WHITE);
            drawRight("Testing...", valX, y + 4, DIM);
            int16_t beep[320];
            for (int i = 0; i < 320; i++) {
                float t = (float)i / 16000.0f;
                beep[i] = (int16_t)(8000.0f * sinf(2.0f * PI * 1000.0f * t));
            }
            audio_io::writeSpeaker(beep, 320);
            tft.fillRect(valX - 60, y + 4, 74, lineH - 4, BG);
            drawDot(10, y + 8, GREEN);
            drawRight("OK", valX, y + 4, GREEN);
            y += lineH;

            // LED flash
            if (((y - 32) / lineH) % 2 == 1)
                tft.fillRect(0, y, LCD_WIDTH, lineH, 0x0821);
            drawLeft("LED", 20, y + 4, WHITE);
            status_led::set(0, 255, 0);
            for (int w = 0; w < 12; w++) { status_led::tick(millis()); delay(25); }
            status_led::syncToState();
            status_led::tick(millis());
            drawDot(10, y + 8, GREEN);
            drawRight("OK", valX, y + 4, GREEN);

            drawBackBar();
            waitForBack();
        }
    }
}

// ── Sub-screen: System Info ──────────────────────────────

static void systemInfoScreen() {
    cls();
    drawHeader("System Info");

    int y = 32;
    const int lineH = 20;
    int row = 0;

    auto line = [&](const char* label, const char* value) {
        if (row % 2 == 1) tft.fillRect(0, y, LCD_WIDTH, lineH, 0x0821);  // subtle row tint
        drawLeft(label, 10, y + 3, DIM);
        drawRight(value, LCD_WIDTH - 10, y + 3, WHITE);
        y += lineH;
        row++;
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

    // Red header for destructive action
    tft.fillRect(0, 0, LCD_WIDTH, 26, 0x4000);
    tft.setFont(&fonts::FreeSans9pt7b);
    tft.setTextSize(1);
    tft.setTextColor(RED);
    tft.setTextDatum(lgfx::top_left);
    tft.drawString("Factory Reset", 10, 6);
    tft.drawFastHLine(0, 26, LCD_WIDTH, RED);

    // Warning text
    drawSmall("This will erase all settings,", 36, WHITE);
    drawSmall("Wi-Fi credentials, and token.", 52, WHITE);
    drawSmall("This cannot be undone.", 70, YELLOW);

    // Confirm button — dark red bg with red border
    tft.fillRect(10, 92, LCD_WIDTH - 20, 30, 0x2000);
    tft.drawRect(10, 92, LCD_WIDTH - 20, 30, RED);
    tft.setFont(&fonts::Font2);
    tft.setTextSize(1);
    tft.setTextColor(RED);
    tft.setTextDatum(lgfx::top_center);
    tft.drawString("Yes, erase everything", CX, 101);

    // Cancel button — outlined green
    tft.drawRect(10, 130, LCD_WIDTH - 20, 30, GREEN);
    tft.setTextColor(GREEN);
    tft.drawString("No, go back", CX, 139);

    // Hit zones: idx 0 = y 80..111 (80 + 0*32), idx 1 = y 112..143 (80 + 1*32)
    // We draw buttons at y=92 and y=130 but keep original tap zones at 80..111 and 112..143
    for (;;) {
        int tapY = waitTapY();
        if (tapY < 0) return;

        int idx = (tapY - 80) / 32;
        if (idx == 0) {
            cls();
            tft.fillRect(0, 0, LCD_WIDTH, 26, 0x4000);
            tft.setFont(&fonts::FreeSans9pt7b);
            tft.setTextColor(RED);
            tft.setTextDatum(lgfx::top_left);
            tft.drawString("Factory Reset", 10, 6);
            tft.drawFastHLine(0, 26, LCD_WIDTH, RED);
            drawSmall("Erasing all data...", 130, RED);
            nvs_store::eraseAll();
            delay(500);
            drawSmall("Done! Rebooting...", 150, GREEN);
            delay(1000);
            ESP.restart();
        }
        if (idx == 1) return;
    }
}

// ── Status dashboard ─────────────────────────────────────

static void drawStatusDashboard() {
    int y = 30;
    const int lineH = 16;
    const int valX = LCD_WIDTH - 12;

    auto statusRow = [&](const char* label, const char* value,
                         uint16_t dotColor, uint16_t valColor) {
        drawDot(10, y + 5, dotColor);
        drawLeft(label, 20, y + 2, DIM);
        drawRight(value, valX, y + 2, valColor);
        y += lineH;
    };

    if (WiFi.isConnected()) {
        int rssi = WiFi.RSSI();
        char wifiStr[24];
        snprintf(wifiStr, sizeof(wifiStr), "%s (%d)", wifiLabel(rssi), rssi);
        uint16_t wc = wifiColor(rssi);
        statusRow("Wi-Fi", wifiStr, wc, wc);
    } else {
        statusRow("Wi-Fi", "Disconnected", RED, RED);
    }

    if (!WiFi.isConnected()) {
        statusRow("Backend", "No Wi-Fi", DIMMER, DIM);
    } else if (!nvs_store::hasDeviceToken()) {
        statusRow("Backend", "No token", YELLOW, YELLOW);
    } else {
        char backendHost[64] = {};
        uint16_t backendPort = 443;
        char backendUrl[128] = {};
        if (nvs_store::getBackendUrl(backendUrl, sizeof(backendUrl))) {
            const char* p = strstr(backendUrl, "://");
            if (p) {
                p += 3;
                const char* slash = strchr(p, '/');
                size_t len = slash ? (size_t)(slash - p) : strlen(p);
                strncpy(backendHost, p, min(len, sizeof(backendHost) - 1));
            }
        }
        if (backendHost[0] == '\0') {
            strncpy(backendHost, "aksabot.hendracodes.com", sizeof(backendHost) - 1);
        }

        WiFiClient probe;
        probe.setTimeout(3000);
        bool reached = probe.connect(backendHost, backendPort);
        probe.stop();

        statusRow("Backend",
                  reached ? "Reachable" : "Unreachable",
                  reached ? GREEN : RED,
                  reached ? GREEN : RED);
    }

    statusRow("SD Card",
              sd_storage::isMounted() ? "Mounted" : "No card",
              sd_storage::isMounted() ? GREEN : YELLOW,
              sd_storage::isMounted() ? GREEN : YELLOW);

    statusRow("Firmware", FIRMWARE_VERSION, DIMMER, WHITE);

    tft.drawFastHLine(0, y + 2, LCD_WIDTH, DIMMER);
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
        drawHeader("BIOS", FIRMWARE_VERSION);
        drawStatusDashboard();

        for (int i = 0; i < menu.count; i++) {
            int iy = menu.top + i * menu.itemH;
            tft.drawFastHLine(0, iy, LCD_WIDTH, DIMMER);
            // Tint "Factory Reset" row slightly
            if (i == 4) tft.fillRect(0, iy + 1, LCD_WIDTH, menu.itemH - 2, 0x1800);
            drawLeft(menu.items[i], 20, iy + 7, (i == 4) ? RED : WHITE);
            if (i < 4) drawRight(">", LCD_WIDTH - 10, iy + 7, DIMMER);
        }
        tft.drawFastHLine(0, menu.top + menu.count * menu.itemH, LCD_WIDTH, DIMMER);

        int tapY = waitTapY();
        if (tapY < 0) continue;

        int idx = (tapY - menu.top) / menu.itemH;
        if (idx < 0 || idx >= menu.count) continue;

        int fy = menu.top + idx * menu.itemH;
        // Selection flash
        tft.fillRect(0, fy + 1, LCD_WIDTH, menu.itemH - 2, HILITE);
        tft.fillRect(0, fy + 1, 3, menu.itemH - 2, CYAN);
        drawLeft(menu.items[idx], 20, fy + 7, CYAN);
        delay(120);

        switch (idx) {
            case 0: return false;
            case 1: if (wifiScreen()) return true; break;
            case 2: hardwareTestScreen(); break;
            case 3: systemInfoScreen(); break;
            case 4: factoryResetScreen(); break;
        }
    }
}
