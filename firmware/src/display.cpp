#include "display.h"
#include "face.h"
#include "config.h"
#include <SPI.h>
#include <TFT_eSPI.h>
#include <Arduino.h>
#include "bitmap_font.h"

// ── Internal state ─────────────────────────────────────
static display::Mode currentMode = display::Mode::FACE;
static display::Mode previousMode = display::Mode::FACE;
static display::StatusBar statusBar = {};
static display::PomodoroData pomodoroData = {};
static display::ReminderData reminderData = {};
static display::CountdownData countdownData = {};

static bool sleeping = false;
static uint8_t brightness = 70;
static bool transcriptEnabled = false;
static char transcriptSpeaker[16] = {};
static char transcriptText[128] = {};

// Auto-return timer
static bool autoReturnActive = false;
static uint32_t autoReturnAtMs = 0;

// Rendering rate control
static uint32_t lastRenderMs = 0;
static const uint16_t RENDER_INTERVAL_MS = 33;  // ~30fps

// ── TFT_eSPI display driver ───────────────────────────
static TFT_eSPI tft = TFT_eSPI();
static TFT_eSprite sprite = TFT_eSprite(&tft);  // Off-screen sprite for flicker-free rendering

// Colors
static const uint16_t COL_BG        = TFT_BLACK;
static const uint16_t COL_FACE      = TFT_WHITE;
static const uint16_t COL_EYE       = TFT_WHITE;
static const uint16_t COL_PUPIL     = TFT_BLACK;
static const uint16_t COL_MOUTH     = TFT_WHITE;
static const uint16_t COL_ACCENT    = TFT_CYAN;
static const uint16_t COL_ERROR     = TFT_RED;
static const uint16_t COL_CALM      = TFT_GREEN;
static const uint16_t COL_WARM      = TFT_YELLOW;
static uint16_t COL_DIM;
static uint16_t COL_STATUS_BG;

// Screen center
static const int CX = LCD_WIDTH / 2;
static const int CY = LCD_HEIGHT / 2;

// ── Display hardware implementation ───────────────────

namespace display_hw {

void init() {
    // Backlight on first so we can see any init issues
    pinMode(LCD_BL, OUTPUT);
    digitalWrite(LCD_BL, HIGH);

    // Initialize SPI bus for the LCD
    SPI.begin(LCD_SCLK, LCD_MISO, LCD_MOSI, LCD_CS);

    tft.init();
    tft.invertDisplay(false);  // ILI9341V normal mode
    tft.setRotation(0);        // Portrait: 240 wide x 320 tall
    tft.fillScreen(COL_BG);

    COL_DIM = tft.color565(80, 80, 80);
    COL_STATUS_BG = tft.color565(20, 20, 30);

    // Create full-screen sprite in PSRAM for flicker-free rendering
    sprite.setColorDepth(16);
    if (sprite.createSprite(LCD_WIDTH, LCD_HEIGHT) == nullptr) {
        Serial.println("[Display HW] WARNING: Sprite alloc failed, falling back to direct draw");
    } else {
        Serial.printf("[Display HW] Sprite buffer: %dx%d (%.1fKB in PSRAM)\n",
            LCD_WIDTH, LCD_HEIGHT, (LCD_WIDTH * LCD_HEIGHT * 2) / 1024.0f);
    }

    Serial.println("[Display HW] ILI9341 initialized (240x320)");
}

void clear() {
    tft.fillScreen(COL_BG);
}

void setBacklight(uint8_t level) {
    // This board uses a simple on/off backlight (GPIO 45)
    // For dimming, we could use analogWrite/ledcWrite
    if (level == 0) {
        digitalWrite(LCD_BL, LOW);
    } else {
        digitalWrite(LCD_BL, HIGH);
    }
}

void renderFace(const face::FaceState& fs, const display::StatusBar& status) {
    // Draw to sprite buffer, then push to screen in one shot (no flicker)
    TFT_eSprite& s = sprite.created() ? sprite : (TFT_eSprite&)tft;
    bool useSprite = sprite.created();

    if (useSprite) {
        s.fillSprite(COL_BG);
    } else {
        tft.fillScreen(COL_BG);
    }

    // Choose accent color based on expression
    uint16_t accentCol = COL_ACCENT;
    switch (fs.expression) {
        case face::Expression::OFFLINE:     accentCol = COL_ERROR; break;
        case face::Expression::CONFUSED:    accentCol = COL_WARM; break;
        case face::Expression::ENCOURAGING: accentCol = COL_WARM; break;
        case face::Expression::CALM:        accentCol = COL_CALM; break;
        case face::Expression::FOCUSED:     accentCol = COL_ACCENT; break;
        default: break;
    }

    // ── Eyes ─────────────────────────────────────────
    int eyeY = CY - 30;
    int eyeSpacing = 45;
    int eyeW = 28, eyeH = 32;

    if (fs.eyesOpen) {
        // Open eyes — white ovals with dark pupils
        if (fs.expression == face::Expression::LISTENING) {
            // Wide eyes
            eyeW = 32; eyeH = 36;
        } else if (fs.expression == face::Expression::FOCUSED) {
            // Squinted eyes
            eyeH = 22;
        }

        // Left eye
        s.fillEllipse(CX - eyeSpacing, eyeY, eyeW, eyeH, COL_EYE);
        s.fillCircle(CX - eyeSpacing, eyeY, 8, COL_PUPIL);
        // Right eye
        s.fillEllipse(CX + eyeSpacing, eyeY, eyeW, eyeH, COL_EYE);
        s.fillCircle(CX + eyeSpacing, eyeY, 8, COL_PUPIL);
    } else {
        // Closed eyes — horizontal lines
        s.drawLine(CX - eyeSpacing - eyeW, eyeY, CX - eyeSpacing + eyeW, eyeY, COL_EYE);
        s.drawLine(CX + eyeSpacing - eyeW, eyeY, CX + eyeSpacing + eyeW, eyeY, COL_EYE);
    }

    // ── Mouth ────────────────────────────────────────
    int mouthY = CY + 40;

    if (fs.expression == face::Expression::SLEEPING) {
        s.setTextColor(COL_DIM, COL_BG);
        s.setTextDatum(MC_DATUM);
        s.setTextSize(2);
        int zOffset = (int)(fs.breathPhase * 10);
        s.drawString("z", CX + 50, eyeY - 20 - zOffset);
        s.setTextSize(3);
        s.drawString("Z", CX + 65, eyeY - 40 - zOffset);
    } else if (fs.expression == face::Expression::CONFUSED) {
        for (int x = -30; x < 30; x += 2) {
            int y = mouthY + (int)(sin(x * 0.3) * 5);
            s.drawPixel(CX + x, y, COL_MOUTH);
            s.drawPixel(CX + x, y + 1, COL_MOUTH);
        }
        s.setTextColor(COL_WARM, COL_BG);
        s.setTextDatum(MC_DATUM);
        s.setTextSize(3);
        s.drawString("?", CX + 70, eyeY - 30);
    } else {
        int mouthOpen = (int)(fs.mouthOpenness * 20);
        if (mouthOpen < 3) {
            for (int x = -25; x <= 25; x++) {
                int y = mouthY + (x * x) / 120;
                s.drawPixel(CX + x, y, COL_MOUTH);
                s.drawPixel(CX + x, y + 1, COL_MOUTH);
            }
        } else {
            s.fillEllipse(CX, mouthY, 25, mouthOpen, COL_MOUTH);
            s.fillEllipse(CX, mouthY, 20, mouthOpen - 3, COL_BG);
        }
    }

    // ── Thinking dots ────────────────────────────────
    if (fs.expression == face::Expression::THINKING) {
        int dotY = mouthY + 10;
        for (int i = 0; i < 3; i++) {
            uint16_t col = (i < fs.thinkingDotCount) ? COL_ACCENT : COL_DIM;
            s.fillCircle(CX - 15 + (i * 15), dotY, 4, col);
        }
    }

    // ── Listening indicator ──────────────────────────
    if (fs.expression == face::Expression::LISTENING) {
        uint32_t phase = millis() % 1000;
        int radius = 8 + (int)(sin(phase * 0.00628) * 4);
        s.fillCircle(CX, LCD_HEIGHT - 40, radius, COL_ACCENT);
    }

    // ── Status bar (top) — bitmap font ────────────────
    s.fillRect(0, 0, LCD_WIDTH, 20, COL_STATUS_BG);
    drawStringBitmap(s, 4, 3, status.wifiConnected ? "WiFi" : "NoWiFi",
                     status.wifiConnected ? COL_CALM : COL_ERROR, 2);
    drawStringBitmap(s, 90, 3, status.wsConnected ? "WS" : "--",
                     status.wsConnected ? COL_CALM : COL_ERROR, 2);

    // ── State label (bottom) — bitmap font ──────────
    const char* stateLabel = "Ready";
    uint16_t labelColor = COL_DIM;
    switch (fs.expression) {
        case face::Expression::IDLE:        stateLabel = "Ready"; break;
        case face::Expression::LISTENING:   stateLabel = "Listening..."; labelColor = COL_ACCENT; break;
        case face::Expression::THINKING:    stateLabel = "Thinking..."; labelColor = COL_WARM; break;
        case face::Expression::SPEAKING:    stateLabel = "Speaking"; labelColor = COL_CALM; break;
        case face::Expression::SLEEPING:    stateLabel = "Sleeping"; break;
        case face::Expression::OFFLINE:     stateLabel = "Offline"; labelColor = COL_ERROR; break;
        case face::Expression::CONFUSED:    stateLabel = "Hmm?"; labelColor = COL_WARM; break;
        case face::Expression::ENCOURAGING: stateLabel = "Hey!"; labelColor = COL_WARM; break;
        case face::Expression::CALM:        stateLabel = "Relax"; labelColor = COL_CALM; break;
        case face::Expression::FOCUSED:     stateLabel = "Focus"; labelColor = COL_ACCENT; break;
    }
    drawStringBitmapCentered(s, CX, LCD_HEIGHT - 30, stateLabel, labelColor, 2);

    if (fs.expression == face::Expression::IDLE) {
        drawStringBitmapCentered(s, CX, LCD_HEIGHT - 12, "Hold to talk", COL_DIM, 1);
    }

    // Push sprite to screen in one shot — no flicker
    if (useSprite) {
        sprite.pushSprite(0, 0);
    }
}

void renderClock(const display::StatusBar& status) {
    tft.fillScreen(COL_BG);

    // Large time
    tft.setTextDatum(MC_DATUM);
    tft.setTextSize(5);
    tft.setTextColor(COL_FACE);

    // Get current time (placeholder — needs RTC or NTP)
    uint32_t sec = millis() / 1000;
    uint8_t h = (sec / 3600) % 24;
    uint8_t m = (sec / 60) % 60;
    char timeBuf[8];
    snprintf(timeBuf, sizeof(timeBuf), "%02d:%02d", h, m);
    tft.drawString(timeBuf, CX, CY - 20);

    // Date placeholder
    tft.setTextSize(2);
    tft.setTextColor(COL_DIM);
    tft.drawString("Aksabot", CX, CY + 30);
}

void renderPomodoro(const display::PomodoroData& data) {
    tft.fillScreen(COL_BG);

    // Phase label
    tft.setTextDatum(MC_DATUM);
    tft.setTextSize(3);
    bool isFocus = (strcmp(data.phaseLabel, "focus") == 0 || strcmp(data.phaseLabel, "work") == 0);
    tft.setTextColor(isFocus ? COL_ACCENT : COL_CALM);
    tft.drawString(isFocus ? "FOCUS" : "BREAK", CX, 60);

    // Large countdown
    tft.setTextSize(6);
    tft.setTextColor(COL_FACE);
    uint16_t min = data.remainingSeconds / 60;
    uint16_t sec = data.remainingSeconds % 60;
    char timeBuf[8];
    snprintf(timeBuf, sizeof(timeBuf), "%02d:%02d", min, sec);
    tft.drawString(timeBuf, CX, CY);

    // Cycle dots
    int dotY = CY + 60;
    for (uint8_t i = 0; i < data.totalCycles; i++) {
        uint16_t col = (i < data.currentCycle) ? COL_ACCENT : COL_DIM;
        tft.fillCircle(CX - 30 + (i * 20), dotY, 6, col);
    }
}

void renderReminder(const display::ReminderData& data) {
    tft.fillScreen(COL_BG);

    // Icon area
    tft.setTextDatum(MC_DATUM);
    tft.setTextSize(4);
    tft.setTextColor(COL_WARM);
    tft.drawString("!", CX, 60);

    // Reminder text (word-wrapped)
    tft.setTextSize(2);
    tft.setTextColor(COL_FACE);
    tft.setTextDatum(MC_DATUM);

    // Simple center-aligned text (TFT_eSPI handles basic wrapping)
    tft.drawString(data.text, CX, CY);

    // Dismiss hint
    tft.setTextSize(1);
    tft.setTextColor(COL_DIM);
    tft.drawString("tap to dismiss", CX, LCD_HEIGHT - 30);
}

void renderCountdown(const display::CountdownData& data) {
    tft.fillScreen(COL_BG);

    // Large number
    tft.setTextDatum(MC_DATUM);
    tft.setTextSize(8);
    tft.setTextColor(COL_CALM);
    char numBuf[4];
    snprintf(numBuf, sizeof(numBuf), "%d", data.remainingSeconds);
    tft.drawString(numBuf, CX, CY - 20);

    // Instruction
    tft.setTextSize(2);
    tft.setTextColor(COL_FACE);
    tft.drawString(data.instruction, CX, CY + 50);
}

void renderStatus(const display::StatusBar& status) {
    tft.fillScreen(COL_BG);
    tft.setTextDatum(TL_DATUM);
    tft.setTextSize(2);

    int y = 20;
    const int lineH = 28;

    tft.setTextColor(COL_ACCENT);
    tft.drawString("System Status", 10, y); y += lineH + 10;

    tft.setTextColor(COL_FACE);
    tft.drawString(status.wifiConnected ? "WiFi: Connected" : "WiFi: Offline", 10, y);
    y += lineH;

    tft.drawString(status.wsConnected ? "Backend: Online" : "Backend: Offline", 10, y);
    y += lineH;

    char rssBuf[24];
    snprintf(rssBuf, sizeof(rssBuf), "Signal: %d dBm", status.wifiRssi);
    tft.drawString(rssBuf, 10, y); y += lineH;

    if (status.batteryPercent == 255) {
        tft.drawString("Power: USB", 10, y);
    } else {
        char batBuf[16];
        snprintf(batBuf, sizeof(batBuf), "Battery: %d%%", status.batteryPercent);
        tft.drawString(batBuf, 10, y);
    }
}

void renderTranscriptOverlay(const char* speaker, const char* text) {
    // Semi-transparent bar at bottom
    int barH = 60;
    int barY = LCD_HEIGHT - barH;
    tft.fillRect(0, barY, LCD_WIDTH, barH, COL_STATUS_BG);

    tft.setTextDatum(TL_DATUM);
    tft.setTextSize(1);
    tft.setTextColor(COL_ACCENT);
    tft.drawString(speaker, 8, barY + 4);

    tft.setTextColor(COL_FACE);
    tft.setTextSize(1);
    // Truncate text to fit
    char truncBuf[48];
    strncpy(truncBuf, text, sizeof(truncBuf) - 1);
    truncBuf[sizeof(truncBuf) - 1] = '\0';
    tft.drawString(truncBuf, 8, barY + 20);
}

}  // namespace display_hw

// ── Public API ─────────────────────────────────────────

void display::init() {
    display_hw::init();
    face::init();

    currentMode = Mode::FACE;
    sleeping = false;
    brightness = 70;
    display_hw::setBacklight(brightness);

    Serial.println("[Display] Initialized — face mode");
}

void display::tick(uint32_t nowMs) {
    if (sleeping) return;

    // Rate-limit rendering
    if ((nowMs - lastRenderMs) < RENDER_INTERVAL_MS) return;
    lastRenderMs = nowMs;

    // Advance face animation
    face::tick(nowMs);

    // Check auto-return timer
    if (autoReturnActive && nowMs >= autoReturnAtMs) {
        autoReturnActive = false;
        currentMode = previousMode;
    }

    // Render current mode
    switch (currentMode) {
        case Mode::FACE:
            display_hw::renderFace(face::getState(), statusBar);
            break;
        case Mode::CLOCK:
            display_hw::renderClock(statusBar);
            break;
        case Mode::POMODORO:
            display_hw::renderPomodoro(pomodoroData);
            break;
        case Mode::REMINDER:
            display_hw::renderReminder(reminderData);
            break;
        case Mode::COUNTDOWN:
            display_hw::renderCountdown(countdownData);
            break;
        case Mode::STATUS:
            display_hw::renderStatus(statusBar);
            break;
    }

    if (transcriptEnabled && transcriptText[0] != '\0') {
        display_hw::renderTranscriptOverlay(transcriptSpeaker, transcriptText);
    }
}

void display::setMode(Mode mode) {
    if (mode == currentMode && !autoReturnActive) return;
    previousMode = currentMode;
    currentMode = mode;
    autoReturnActive = false;
    if (sleeping) wake();
}

display::Mode display::getMode() {
    return currentMode;
}

void display::setModeTemporary(Mode mode, uint16_t durationMs) {
    previousMode = currentMode;
    currentMode = mode;
    autoReturnActive = true;
    autoReturnAtMs = millis() + durationMs;
    if (sleeping) wake();
}

void display::updateStatusBar(const StatusBar& status) {
    statusBar = status;
}

void display::showPomodoro(const PomodoroData& data) {
    pomodoroData = data;
    setMode(Mode::POMODORO);
}

void display::showReminder(const ReminderData& data) {
    reminderData = data;
    setModeTemporary(Mode::REMINDER, data.durationMs > 0 ? data.durationMs : 5000);
}

void display::showCountdown(const CountdownData& data) {
    countdownData = data;
    setMode(Mode::COUNTDOWN);
}

void display::setTranscriptOverlay(bool enabled) {
    transcriptEnabled = enabled;
}

void display::setTranscriptText(const char* speaker, const char* text) {
    strncpy(transcriptSpeaker, speaker, sizeof(transcriptSpeaker) - 1);
    transcriptSpeaker[sizeof(transcriptSpeaker) - 1] = '\0';
    strncpy(transcriptText, text, sizeof(transcriptText) - 1);
    transcriptText[sizeof(transcriptText) - 1] = '\0';
}

void display::setBrightness(uint8_t level) {
    brightness = level;
    display_hw::setBacklight(level);
}

bool display::isSleeping() {
    return sleeping;
}

void display::sleep() {
    if (sleeping) return;
    sleeping = true;
    display_hw::setBacklight(0);
    face::setExpression(face::Expression::SLEEPING, 500);
}

void display::wake() {
    if (!sleeping) return;
    sleeping = false;
    display_hw::setBacklight(brightness);
    face::setExpression(face::Expression::IDLE, 300);
    setMode(Mode::FACE);
}
