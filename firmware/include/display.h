#pragma once
#include "face.h"
#include <cstdint>

/// Display manager — controls modes, rendering, and status bar.
///
/// Architecture:
///   display::tick()  →  reads face::getState()  →  calls display_hw functions
///
/// The display_hw layer is a thin shim over the actual TFT driver.
/// Replace its implementation when hardware is available.
namespace display {

/// Display modes.
enum class Mode : uint8_t {
    FACE,           // Full-screen animated face + status bar
    CLOCK,          // Large time, date, next reminder, mini face
    POMODORO,       // Phase label, countdown, cycle dots
    REMINDER,       // Reminder icon, text, "tap to dismiss"
    COUNTDOWN,      // Large countdown number (eye break 20s)
    STATUS,         // Wi-Fi, battery, uptime, stats
    GLANCE,         // Temporary idle screen — time + weather
};

/// Status bar data (visible in face and clock modes).
struct StatusBar {
    int8_t wifiRssi;            // Wi-Fi signal strength (-30 to -90)
    bool wifiConnected;
    bool wsConnected;
    bool connectionStalled;     // Data flow stalled during active state
    uint8_t batteryPercent;     // 0-100 or 255 = USB-powered
    bool focusModeActive;
    bool pomodoroActive;
    uint8_t pomodoroCycle;      // 1-4
};

/// Pomodoro display data.
struct PomodoroData {
    char phaseLabel[16];        // "FOCUS" or "BREAK"
    uint16_t remainingSeconds;
    uint8_t currentCycle;       // 1-based
    uint8_t totalCycles;
};

/// Reminder display data.
struct ReminderData {
    char text[64];
    char icon[16];              // Icon name hint for renderer
    uint16_t durationMs;        // Auto-dismiss after this
};

/// Countdown display data.
struct CountdownData {
    uint8_t remainingSeconds;
    char instruction[48];       // e.g., "Look at something 20ft away"
};

/// Glance display data (time + weather from backend context:sync).
struct GlanceData {
    char time[8];           // "14:35"
    char date[16];          // "Sat, 12 Apr"
    char weather[24];       // "Partly cloudy"
    int8_t temp;            // °C
    uint8_t humidity;       // %
    uint8_t weatherCode;    // WMO code for icon selection
    bool hasWeather;        // false = time-only glance
};

/// Initialize display hardware and start with face mode.
void init();

/// Advance display state. Call from display task (30fps recommended).
void tick(uint32_t nowMs);

/// Set display mode. Saves previous mode for auto-return.
void setMode(Mode mode);

/// Get current display mode.
Mode getMode();

/// Set mode with auto-return after durationMs.
/// After the timeout, returns to the previous mode.
void setModeTemporary(Mode mode, uint16_t durationMs);

/// Update status bar data.
void updateStatusBar(const StatusBar& status);

/// Set pomodoro display data.
void showPomodoro(const PomodoroData& data);

/// Set reminder display data.
void showReminder(const ReminderData& data);

/// Set countdown display data.
void showCountdown(const CountdownData& data);

/// Enable/disable transcript overlay on top of current mode.
void setTranscriptOverlay(bool enabled);

/// Set transcript text (STT or LLM response).
void setTranscriptText(const char* speaker, const char* text);

/// Set display brightness (0-100). 0 = off (sleep).
void setBrightness(uint8_t brightness);

/// Smoothly fade display brightness to target over durationMs.
/// Non-blocking — runs inside tick(). Subsequent calls override the active fade.
void fadeBrightness(uint8_t target, uint16_t durationMs = 300);

/// Returns true if a fade transition is currently in progress.
bool isFading();

/// Check if display is currently off (sleeping).
bool isSleeping();

/// Turn display off (sleep) with fade-out.
void sleep();

/// Turn display on (wake) with fade-in.
void wake();

/// Store latest context data from backend (does not trigger display).
void updateContextData(const GlanceData& data);

/// Show glance screen (time + weather) temporarily, then auto-return.
void showGlance();

/// Check if context data is available for glance display.
bool hasContextData();

}  // namespace display
