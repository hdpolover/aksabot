#include "boot_screen.h"
#include "config.h"
#include "lgfx_config.h"
#include "touch.h"
#include <Arduino.h>

extern LGFX tft;

// ── Color palette ─────────────────────────────────────────
// Previously CYAN was mistakenly set to TFT_WHITE. All screens now use
// real cyan as intended. BG is near-black with a subtle blue tint.
static const uint16_t BG       = TFT_BLACK; // pure black
static const uint16_t WHITE    = TFT_WHITE;
static const uint16_t CYAN     = 0x07FF;   // bright cyan
static const uint16_t CYAN_DIM = 0x05EF;   // medium cyan (tagline, accents)
static const uint16_t GREEN    = 0x07E0;
static const uint16_t RED      = TFT_RED;
static const uint16_t YELLOW   = TFT_YELLOW;
static const uint16_t DIM      = 0x8C71;   // medium gray (secondary text)
static const uint16_t DIM_DARK = 0x4228;   // dark gray (version, hints)

// Glow gradient — outermost to innermost, just outside the face ring
static const uint16_t GLOW_1   = 0x0071;   // barely-there dark teal (outer)
static const uint16_t GLOW_2   = 0x00F3;   // dark teal
static const uint16_t GLOW_3   = 0x0195;   // medium teal
static const uint16_t GLOW_4   = 0x0247;   // bright teal (inner edge of glow)

static const int CX = LCD_WIDTH / 2;
static int hwCheckY = 0;

// ── Helpers ───────────────────────────────────────────────

static void clearScreen() {
    tft.fillScreen(BG);
}

static void drawCentered(const char* text, int y, uint16_t color, float size = 1.0f) {
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

// ── Public API ────────────────────────────────────────────

void boot_screen::init() {
    clearScreen();
    tft.setBrightness(180);
    tft.setTextSize(1);
}

void boot_screen::showSplash(const char* version) {
    clearScreen();

    drawCentered("Aksabot", 112, WHITE, 1.6f);
    tft.drawFastHLine(CX - 56, 142, 112, GLOW_4);
    drawSmall("AI Desk Companion", 152, CYAN_DIM);

    char versionStr[24];
    snprintf(versionStr, sizeof(versionStr), "v%s", version);
    drawSmall(versionStr, 174, DIM_DARK);

    delay(1500);
}

void boot_screen::showSplashWithBootCheck(const char* version) {
    clearScreen();

    // ── Title & tagline ──────────────────────────────────
    drawCentered("Aksabot", 88, WHITE, 1.6f);
    tft.drawFastHLine(CX - 56, 118, 112, GLOW_4);
    drawSmall("AI Desk Companion", 128, CYAN_DIM);

    char versionStr[24];
    snprintf(versionStr, sizeof(versionStr), "v%s", version);
    drawSmall(versionStr, 150, DIM_DARK);

    // ── Decoration dots ───────────────────────────────────
    tft.fillCircle(CX - 18, 200, 2, GLOW_4);
    tft.fillCircle(CX,      200, 2, GLOW_4);
    tft.fillCircle(CX + 18, 200, 2, GLOW_4);

    // ── Boot progress bar ─────────────────────────────────
    const int barX = 30;
    const int barY = 240;
    const int barW = LCD_WIDTH - 60;
    const int barH = 5;
    tft.drawRoundRect(barX - 1, barY - 1, barW + 2, barH + 2, 3, GLOW_2);

    drawSmall("Hold BOOT for BIOS", 254, DIM_DARK);

    // ── 2-second BIOS window ─────────────────────────────
    const uint32_t durationMs = 2000;
    const uint32_t startMs = millis();

    while ((millis() - startMs) < durationMs) {
        uint32_t elapsed = millis() - startMs;

        int fillW = (int)((elapsed * barW) / durationMs);
        if (fillW > 0) {
            tft.fillRoundRect(barX, barY, fillW, barH, 2, CYAN);
        }

        if (digitalRead(BOOT_BUTTON_PIN) == LOW) {
            tft.fillRoundRect(barX, barY, barW, barH, 2, GREEN);
            tft.fillRect(0, 250, LCD_WIDTH, 20, BG);
            drawSmall("Entering BIOS...", 254, GREEN);
            while ((millis() - startMs) < durationMs) {
                delay(20);
            }
            return;
        }

        delay(20);
    }

    tft.fillRoundRect(barX, barY, barW, barH, 2, CYAN);
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

    drawCentered("Aksabot", 92, WHITE, 1.6f);
    tft.drawFastHLine(CX - 56, 122, 112, GLOW_4);
    drawSmall("Your AI desk companion", 132, CYAN_DIM);

    tft.drawFastHLine(30, 174, LCD_WIDTH - 60, GLOW_3);

    drawSmall("Open the Aksabot app on your", 186, DIM);
    drawSmall("phone to get started.", 204, DIM);

    delay(2500);
}

void boot_screen::showProvisioningPrompt(const char* apName) {
    clearScreen();

    // Bluetooth icon (simplified diamond shape)
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
        drawSmall("Open the Aksabot app", 155, DIM);
        drawSmall("— or connect to Wi-Fi —", 173, DIM);
        char apLine[48];
        snprintf(apLine, sizeof(apLine), "\"%s\"", apName);
        drawSmall(apLine, 191, CYAN);
    } else {
        drawSmall("Open the Aksabot app", 158, DIM);
        drawSmall("to connect this device", 178, DIM);
    }

    drawSmall("Waiting...", 225, DIM);
}

void boot_screen::showProvisioningConnected() {
    clearScreen();

    // Phone icon
    int phoneY = 40;
    tft.drawRoundRect(CX - 14, phoneY, 28, 48, 4, GREEN);
    tft.drawFastHLine(CX - 8, phoneY + 4, 16, GREEN);
    tft.drawFastHLine(CX - 8, phoneY + 40, 16, GREEN);
    tft.fillCircle(CX, phoneY + 44, 2, GREEN);

    // Checkmark
    tft.drawLine(CX + 22, phoneY + 18, CX + 28, phoneY + 26, GREEN);
    tft.drawLine(CX + 28, phoneY + 26, CX + 40, phoneY + 12, GREEN);

    drawCentered("Phone Connected", 100, WHITE);
    drawSmall("Setting up your Aksabot...", 128, DIM);

    tft.drawFastHLine(30, 152, LCD_WIDTH - 60, GLOW_3);

    drawSmall("Select your Wi-Fi network", 164, CYAN_DIM);
    drawSmall("in the app to continue.", 184, DIM);

    drawSmall("Waiting for Wi-Fi...", 225, DIM);
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

    int dotY = 245;
    int spacing = 14;
    for (int i = 0; i < 3; i++) {
        uint16_t col = (i == phase) ? CYAN : DIM;
        tft.fillCircle(CX + (i - 1) * spacing, dotY, 4, col);
    }
}

void boot_screen::showConnecting(const char* ssid) {
    clearScreen();

    // WiFi concentric arc icon
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

    // Glowing green checkmark circle
    tft.fillCircle(CX, 90, 36, 0x0240);   // dark green glow
    tft.fillCircle(CX, 90, 30, 0x03E0);   // medium green glow
    tft.fillCircle(CX, 90, 26, BG);        // face interior
    tft.drawCircle(CX, 90, 26, GREEN);
    tft.drawCircle(CX, 90, 25, GREEN);     // 2px ring

    // Checkmark inside the circle
    for (int i = -1; i <= 1; i++) {
        tft.drawLine(CX - 13, 90 + i, CX - 3, 103 + i, GREEN);
        tft.drawLine(CX - 3,  103 + i, CX + 16, 80 + i, GREEN);
    }

    drawCentered("Ready!", 134, WHITE, 1.2f);
    drawSmall("Hold screen to talk", 166, CYAN_DIM);

    delay(1500);
}

void boot_screen::showRebootingForSetup() {
    clearScreen();

    // Circular arrow / sync icon
    int iconCY = 80;
    int r = 22;
    for (int a = 120; a <= 360; a += 3) {
        float rad = a * 3.14159f / 180.0f;
        int x = CX + (int)(r * cosf(rad));
        int y = iconCY + (int)(r * sinf(rad));
        tft.drawPixel(x, y, CYAN);
        tft.drawPixel(x + 1, y, CYAN);
        tft.drawPixel(x, y + 1, CYAN);
    }
    // Arrowhead
    tft.drawLine(CX + r - 2, iconCY + 8, CX + r + 7, iconCY,      CYAN);
    tft.drawLine(CX + r - 2, iconCY + 8, CX + r - 2, iconCY + 16, CYAN);

    drawCentered("Entering Setup Mode", 118, WHITE, 1.0f);
    drawSmall("Requested from the app.", 148, DIM);
    drawSmall("Rebooting in a moment...", 168, DIM);
}

bool boot_screen::showBiosCountdown() {
    clearScreen();

    // Gear icon
    int gearY = 70;
    tft.drawCircle(CX, gearY, 18, DIM);
    tft.drawCircle(CX, gearY, 12, DIM);
    tft.fillCircle(CX, gearY, 6, DIM);
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

    // Progress bar
    const int barX = 30;
    const int barY = 165;
    const int barW = LCD_WIDTH - 60;
    const int barH = 8;
    tft.drawRoundRect(barX - 1, barY - 1, barW + 2, barH + 2, 3, DIM);

    const uint32_t durationMs = 2000;
    const uint32_t startMs = millis();
    bool held = false;

    while ((millis() - startMs) < durationMs) {
        uint32_t elapsed = millis() - startMs;

        // Drain left-to-right
        int fillW = barW - (int)((elapsed * barW) / durationMs);
        if (fillW < 0) fillW = 0;
        tft.fillRoundRect(barX, barY, fillW, barH, 2, CYAN);
        if (fillW < barW) {
            tft.fillRect(barX + fillW, barY, barW - fillW, barH, BG);
        }

        touch::tick(millis());
        touch::processSerial(millis());

        if (touch::isTouched()) {
            held = true;
            tft.fillRoundRect(barX, barY, fillW, barH, 2, GREEN);
            tft.fillRect(0, 128, LCD_WIDTH, 20, BG);
            drawSmall("Entering BIOS...", 130, GREEN);
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

    // Circle with checkmark
    int cy = 80;
    tft.drawCircle(CX, cy + 5, 34, GREEN);
    tft.drawCircle(CX, cy + 5, 33, GREEN);
    for (int i = -1; i <= 1; i++) {
        tft.drawLine(CX - 16, cy + 5 + i, CX - 5, cy + 20 + i, GREEN);
        tft.drawLine(CX - 5, cy + 20 + i, CX + 18, cy - 8 + i, GREEN);
    }

    drawCentered("All Set!", 132, WHITE, 1.2f);

    char ssidLine[36];
    snprintf(ssidLine, sizeof(ssidLine), "\"%s\"", ssid);
    drawSmall(ssidLine, 162, CYAN);
    drawSmall("Connected to the internet", 182, DIM);

    tft.drawFastHLine(30, 206, LCD_WIDTH - 60, GLOW_3);
    drawSmall("Starting Aksabot...", 216, DIM);

    delay(2500);
}
