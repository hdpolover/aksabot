#include "boot_screen.h"
#include "config.h"
#include "lgfx_config.h"
#include "touch.h"
#include <Arduino.h>

extern LGFX tft;

// Colors (RGB565)
static const uint16_t BG      = TFT_BLACK;
static const uint16_t WHITE   = TFT_WHITE;
static const uint16_t CYAN    = TFT_WHITE;
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

void boot_screen::showSplashWithBootCheck(const char* version) {
    clearScreen();

    // Robot face logo (same as showSplash)
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

    // BOOT button hint
    drawSmall("Press BOOT for BIOS", 220, DIM);

    // Poll GPIO 0 for 2 seconds during splash
    uint32_t start = millis();
    bool detected = false;
    while ((millis() - start) < 2000) {
        if (digitalRead(BOOT_BUTTON_PIN) == LOW) {
            detected = true;
            // Visual feedback
            tft.fillRect(0, 215, LCD_WIDTH, 25, BG);
            drawSmall("Entering BIOS...", 220, GREEN);
            delay(500);
            break;
        }
        delay(20);
    }

    if (!detected) {
        // Normal boot — brief pause then continue
        uint32_t elapsed = millis() - start;
        if (elapsed < 1500) delay(1500 - elapsed);
    }
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

void boot_screen::showFirstBoot() {
    clearScreen();

    // Robot icon — larger than splash, with "arms" to feel friendly
    int logoY = 42;
    tft.drawRoundRect(CX - 28, logoY, 56, 42, 7, CYAN);
    tft.fillCircle(CX - 11, logoY + 14, 5, CYAN);
    tft.fillCircle(CX + 11, logoY + 14, 5, CYAN);
    tft.drawLine(CX - 9, logoY + 30, CX + 9, logoY + 30, CYAN);
    // Antenna
    tft.drawLine(CX, logoY, CX, logoY - 10, CYAN);
    tft.fillCircle(CX, logoY - 13, 3, CYAN);
    // Arms
    tft.drawLine(CX - 28, logoY + 16, CX - 40, logoY + 26, CYAN);
    tft.fillCircle(CX - 41, logoY + 27, 3, CYAN);
    tft.drawLine(CX + 28, logoY + 16, CX + 40, logoY + 26, CYAN);
    tft.fillCircle(CX + 41, logoY + 27, 3, CYAN);

    drawCentered("Hello! I'm Aksabot", 100, WHITE);
    drawSmall("Your AI desk companion", 124, CYAN);

    tft.drawFastHLine(30, 148, LCD_WIDTH - 60, DIM);

    drawSmall("Open the Aksabot app on your", 160, DIM);
    drawSmall("phone to get started.", 178, DIM);

    delay(2500);
}

void boot_screen::showProvisioningPrompt(const char* apName) {
    clearScreen();

    // Bluetooth icon
    int iconY = 40;
    int s = 9;
    tft.drawLine(CX, iconY, CX + s, iconY + s*2, CYAN);
    tft.drawLine(CX + s, iconY + s*2, CX - s, iconY + s*4, CYAN);
    tft.drawLine(CX - s, iconY + s*4, CX + s, iconY + s*6, CYAN);
    tft.drawLine(CX + s, iconY + s*6, CX, iconY + s*8, CYAN);
    tft.drawLine(CX, iconY, CX, iconY + s*8, CYAN);
    tft.drawLine(CX, iconY, CX - s, iconY + s*2, CYAN);
    tft.drawLine(CX - s, iconY + s*2, CX, iconY + s*4, CYAN);
    tft.drawLine(CX, iconY + s*4, CX - s, iconY + s*6, CYAN);
    tft.drawLine(CX - s, iconY + s*6, CX, iconY + s*8, CYAN);

    drawCentered("Setup Required", 132, WHITE);

    if (apName && strlen(apName) > 0) {
        // Both BLE and SoftAP available
        drawSmall("Open the Aksabot app", 155, DIM);
        drawSmall("— or connect to Wi-Fi —", 173, DIM);
        char apLine[48];
        snprintf(apLine, sizeof(apLine), "\"%s\"", apName);
        drawSmall(apLine, 191, CYAN);
    } else {
        // BLE only
        drawSmall("Open the Aksabot app", 158, DIM);
        drawSmall("to connect this device", 178, DIM);
    }

    // Animated dots slot (updated by tickProvisioningAnimation)
    drawSmall("Waiting...", 225, DIM);
}

void boot_screen::showProvisioningStatus(const char* status) {
    tft.fillRect(0, 250, LCD_WIDTH, 40, BG);
    tft.fillCircle(CX, 245, 3, GREEN);
    drawSmall(status, 260, GREEN);
}

void boot_screen::tickProvisioningAnimation(uint32_t nowMs) {
    static uint32_t lastMs = 0;
    static uint8_t phase = 0;

    if (nowMs - lastMs < 500) return;
    lastMs = nowMs;
    phase = (phase + 1) % 3;

    // Three cycling dots just below the "Waiting..." label to show life
    int dotY = 245;
    int spacing = 14;
    for (int i = 0; i < 3; i++) {
        // Dim all three then highlight the active one
        uint16_t col = (i == phase) ? CYAN : DIM;
        tft.fillCircle(CX + (i - 1) * spacing, dotY, 4, col);
    }
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

    delay(500);
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

bool boot_screen::showBiosCountdown() {
    // Draw the countdown UI
    clearScreen();

    // Gear icon (simple representation)
    int gearY = 70;
    tft.drawCircle(CX, gearY, 18, DIM);
    tft.drawCircle(CX, gearY, 12, DIM);
    tft.fillCircle(CX, gearY, 6, DIM);
    // Gear teeth
    for (int a = 0; a < 360; a += 45) {
        float rad = a * PI / 180.0f;
        int x1 = CX + (int)(16 * cosf(rad));
        int y1 = gearY + (int)(16 * sinf(rad));
        int x2 = CX + (int)(22 * cosf(rad));
        int y2 = gearY + (int)(22 * sinf(rad));
        tft.drawLine(x1, y1, x2, y2, DIM);
    }

    drawCentered("Hold for BIOS", 105, WHITE);
    drawSmall("Release to continue boot", 130, DIM);

    // Progress bar background
    const int barX = 30;
    const int barY = 165;
    const int barW = LCD_WIDTH - 60;
    const int barH = 8;
    tft.drawRoundRect(barX - 1, barY - 1, barW + 2, barH + 2, 3, DIM);

    // 2-second countdown, polling touch every 20ms
    const uint32_t durationMs = 2000;
    const uint32_t startMs = millis();
    bool held = false;

    while ((millis() - startMs) < durationMs) {
        uint32_t elapsed = millis() - startMs;

        // Update progress bar (drains left to right)
        int fillW = barW - (int)((elapsed * barW) / durationMs);
        if (fillW < 0) fillW = 0;
        tft.fillRoundRect(barX, barY, fillW, barH, 2, CYAN);
        // Clear the emptied portion
        if (fillW < barW) {
            tft.fillRect(barX + fillW, barY, barW - fillW, barH, BG);
        }

        // Poll touch
        touch::tick(millis());
        touch::processSerial(millis());

        if (touch::isTouched()) {
            held = true;
            // Visual feedback — change bar color and text
            tft.fillRoundRect(barX, barY, fillW, barH, 2, GREEN);
            tft.fillRect(0, 128, LCD_WIDTH, 20, BG);
            drawSmall("Entering BIOS...", 130, GREEN);
            // Wait for the bar to finish with green
            while ((millis() - startMs) < durationMs) {
                elapsed = millis() - startMs;
                fillW = barW - (int)((elapsed * barW) / durationMs);
                if (fillW < 0) fillW = 0;
                tft.fillRoundRect(barX, barY, fillW, barH, 2, GREEN);
                if (fillW < barW) {
                    tft.fillRect(barX + fillW, barY, barW - fillW, barH, BG);
                }
                delay(20);
            }
            break;
        }

        delay(20);
    }

    return held;
}

void boot_screen::showSetupComplete(const char* ssid) {
    clearScreen();

    // Circle with checkmark — completion feel
    int cy = 80;
    tft.drawCircle(CX, cy + 5, 34, GREEN);
    tft.drawCircle(CX, cy + 5, 33, GREEN);  // double-stroke
    for (int i = -1; i <= 1; i++) {
        tft.drawLine(CX - 16, cy + 5 + i, CX - 5, cy + 20 + i, GREEN);
        tft.drawLine(CX - 5, cy + 20 + i, CX + 18, cy - 8 + i, GREEN);
    }

    drawCentered("All Set!", 132, WHITE, 1.2);

    // SSID line — truncate if too long
    char ssidLine[36];
    snprintf(ssidLine, sizeof(ssidLine), "\"%s\"", ssid);
    drawSmall(ssidLine, 162, CYAN);
    drawSmall("Connected to the internet", 182, DIM);

    tft.drawFastHLine(30, 206, LCD_WIDTH - 60, DIM);
    drawSmall("Starting Aksabot...", 216, DIM);

    delay(2500);
}
