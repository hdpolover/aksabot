#include "boot_screen.h"
#include "config.h"
#include "lgfx_config.h"
#include <Arduino.h>

extern LGFX tft;

// Colors (RGB565)
static const uint16_t BG      = TFT_BLACK;
static const uint16_t WHITE   = TFT_WHITE;
static const uint16_t CYAN    = TFT_CYAN;
static const uint16_t GREEN   = 0x07E0;
static const uint16_t RED     = TFT_RED;
static const uint16_t YELLOW  = TFT_YELLOW;
static const uint16_t DIM     = 0x8C71;  // brighter gray for readability

static const int CX = LCD_WIDTH / 2;
static int hwCheckY = 0;

// ── Helpers ──────────────────────────────────────────────

static void clearScreen() {
    tft.fillScreen(BG);
}

// Draw text centered, using FreeSans for good readability
static void drawCentered(const char* text, int y, uint16_t color, float size = 1.0) {
    tft.setTextColor(color);
    tft.setFont(&fonts::FreeSans9pt7b);
    tft.setTextSize(size);
    tft.setTextDatum(lgfx::top_center);
    tft.drawString(text, CX, y);
}

// Draw small text centered
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

// ── Public API ──────────────────────────────────────────

void boot_screen::init() {
    clearScreen();
    tft.setBrightness(180);  // slightly dimmer to reduce washout
    tft.setTextSize(1);
}

void boot_screen::showSplash(const char* version) {
    clearScreen();

    // Robot face logo
    int logoY = 70;
    tft.drawRoundRect(CX - 25, logoY, 50, 38, 6, CYAN);
    tft.fillCircle(CX - 10, logoY + 14, 4, CYAN);
    tft.fillCircle(CX + 10, logoY + 14, 4, CYAN);
    tft.drawLine(CX - 8, logoY + 28, CX + 8, logoY + 28, CYAN);
    tft.drawLine(CX, logoY, CX, logoY - 10, CYAN);
    tft.fillCircle(CX, logoY - 12, 3, CYAN);

    drawCentered("AKSABOT", 120, WHITE, 1.2);

    char versionStr[32];
    snprintf(versionStr, sizeof(versionStr), "v%s", version);
    drawSmall(versionStr, 150, DIM);
    drawSmall("AI Desk Companion", 170, DIM);

    delay(1500);
}

void boot_screen::showHardwareCheck(const char* component, uint8_t status) {
    static bool headerDrawn = false;
    if (!headerDrawn) {
        clearScreen();
        drawCentered("Hardware Check", 6, CYAN);
        tft.drawFastHLine(20, 30, LCD_WIDTH - 40, DIM);
        hwCheckY = 38;
        headerDrawn = true;
    }

    const char* icon;
    uint16_t iconColor;
    switch (status) {
        case 0: icon = "..."; iconColor = YELLOW; break;
        case 1: icon = "OK";  iconColor = GREEN;  break;
        case 2: icon = "FAIL"; iconColor = RED;   break;
        case 3: icon = "SKIP"; iconColor = DIM;   break;
        default: icon = "?";   iconColor = DIM;   break;
    }

    tft.fillRect(8, hwCheckY, LCD_WIDTH - 16, 18, BG);
    drawLeft(component, 12, hwCheckY, WHITE);
    drawRight(icon, LCD_WIDTH - 12, hwCheckY, iconColor);

    if (status != 0) {
        hwCheckY += 20;
    }

    if (hwCheckY > 290) {
        headerDrawn = false;
    }
}

void boot_screen::showProvisioningPrompt() {
    clearScreen();

    // BLE icon (compact Bluetooth shape)
    int iconY = 55;
    int s = 10;
    tft.drawLine(CX, iconY, CX + s, iconY + s*2, CYAN);
    tft.drawLine(CX + s, iconY + s*2, CX - s, iconY + s*4, CYAN);
    tft.drawLine(CX - s, iconY + s*4, CX + s, iconY + s*6, CYAN);
    tft.drawLine(CX + s, iconY + s*6, CX, iconY + s*8, CYAN);
    tft.drawLine(CX, iconY, CX, iconY + s*8, CYAN);
    tft.drawLine(CX, iconY, CX - s, iconY + s*2, CYAN);
    tft.drawLine(CX - s, iconY + s*2, CX, iconY + s*4, CYAN);
    tft.drawLine(CX, iconY + s*4, CX - s, iconY + s*6, CYAN);
    tft.drawLine(CX - s, iconY + s*6, CX, iconY + s*8, CYAN);

    drawCentered("Setup Required", 155, WHITE);
    drawSmall("Open the Aksabot app", 185, DIM);
    drawSmall("to connect this device", 205, DIM);

    tft.fillCircle(CX, 245, 3, CYAN);
    drawSmall("Waiting for connection...", 260, DIM);
}

void boot_screen::showProvisioningStatus(const char* status) {
    tft.fillRect(0, 250, LCD_WIDTH, 40, BG);
    tft.fillCircle(CX, 245, 3, GREEN);
    drawSmall(status, 260, GREEN);
}

void boot_screen::showConnecting(const char* ssid) {
    clearScreen();

    // WiFi icon
    int iconY = 75;
    tft.drawCircle(CX, iconY + 25, 22, CYAN);
    tft.drawCircle(CX, iconY + 25, 15, CYAN);
    tft.drawCircle(CX, iconY + 25, 8, CYAN);
    tft.fillCircle(CX, iconY + 25, 3, CYAN);

    drawCentered("Connecting WiFi", 130, WHITE);

    char ssidStr[48];
    snprintf(ssidStr, sizeof(ssidStr), "\"%s\"", ssid);
    drawSmall(ssidStr, 160, CYAN);
    drawSmall("Please wait...", 185, DIM);
}

void boot_screen::showConnected(const char* ip) {
    tft.fillRect(0, 178, LCD_WIDTH, 60, BG);
    drawSmall("Connected!", 185, GREEN);

    char ipStr[32];
    snprintf(ipStr, sizeof(ipStr), "IP: %s", ip);
    drawSmall(ipStr, 208, DIM);

    delay(1500);
}

void boot_screen::showConnectionFailed(const char* reason) {
    tft.fillRect(0, 178, LCD_WIDTH, 60, BG);
    drawSmall("Connection Failed", 185, RED);
    drawSmall(reason, 208, DIM);
}

void boot_screen::showReady() {
    clearScreen();

    // Checkmark
    int cy = 95;
    tft.drawLine(CX - 14, cy, CX - 4, cy + 14, GREEN);
    tft.drawLine(CX - 4, cy + 14, CX + 18, cy - 8, GREEN);
    tft.drawLine(CX - 13, cy, CX - 3, cy + 14, GREEN);
    tft.drawLine(CX - 3, cy + 14, CX + 19, cy - 8, GREEN);

    drawCentered("Ready!", 125, WHITE, 1.2);
    drawSmall("Hold screen to talk", 158, DIM);

    delay(1500);
}
