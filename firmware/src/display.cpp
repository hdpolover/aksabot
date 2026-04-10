#include "display.h"
#include "face.h"
#include <Arduino.h>

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

// ── Display hardware shim ──────────────────────────────
// TODO: Replace these stubs with actual TFT driver calls (ST7789/ILI9341)
// when hardware is available. The API is intentionally simple so the
// driver can be swapped without changing the display manager logic.

namespace display_hw {

static bool initialized = false;

void init() {
    // TODO: Initialize SPI, TFT controller, set rotation, clear screen
    initialized = true;
    Serial.println("[Display HW] Init (stub — no TFT connected)");
}

void clear() {
    // TODO: Fill screen with background color
}

void setBacklight(uint8_t level) {
    // TODO: PWM backlight control (0=off, 255=full)
    (void)level;
}

void renderFace(const face::FaceState& faceState, const display::StatusBar& status) {
    // TODO: Draw face sprites/shapes based on faceState
    // - Draw eyes (open/closed based on faceState.eyesOpen)
    // - Draw mouth (openness from faceState.mouthOpenness)
    // - Draw thinking dots (faceState.thinkingDotCount)
    // - Draw breathing indicator (faceState.breathPhase for sleeping)
    // - Draw status bar at top
    // - Handle transition blending (faceState.transitionProgress)
    (void)faceState;
    (void)status;
}

void renderClock(const display::StatusBar& status) {
    // TODO: Draw large time (center), date, next reminder, mini face corner
    (void)status;
}

void renderPomodoro(const display::PomodoroData& data) {
    // TODO: Draw phase label, large countdown, cycle dots/progress bar
    (void)data;
}

void renderReminder(const display::ReminderData& data) {
    // TODO: Draw reminder icon, text centered, "tap to dismiss" footer
    (void)data;
}

void renderCountdown(const display::CountdownData& data) {
    // TODO: Draw large countdown number, instruction text below
    (void)data;
}

void renderStatus(const display::StatusBar& status) {
    // TODO: Draw Wi-Fi signal, battery, uptime, stats in a dashboard layout
    (void)status;
}

void renderTranscriptOverlay(const char* speaker, const char* text) {
    // TODO: Draw semi-transparent overlay with transcript text at bottom
    (void)speaker;
    (void)text;
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
        Serial.printf("[Display] Auto-return to mode %u\n", (uint8_t)currentMode);
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

    // Transcript overlay on top of everything
    if (transcriptEnabled && transcriptText[0] != '\0') {
        display_hw::renderTranscriptOverlay(transcriptSpeaker, transcriptText);
    }
}

void display::setMode(Mode mode) {
    if (mode == currentMode && !autoReturnActive) return;
    previousMode = currentMode;
    currentMode = mode;
    autoReturnActive = false;

    Serial.printf("[Display] Mode → %u\n", (uint8_t)mode);

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

    Serial.printf("[Display] Temporary mode %u for %ums\n",
        (uint8_t)mode, durationMs);

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
    Serial.println("[Display] Sleep");
}

void display::wake() {
    if (!sleeping) return;
    sleeping = false;
    display_hw::setBacklight(brightness);
    face::setExpression(face::Expression::IDLE, 300);
    setMode(Mode::FACE);
    Serial.println("[Display] Wake");
}
