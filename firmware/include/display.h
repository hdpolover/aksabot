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
    IMAGE,          // Static image from SD — tick() skips sprite rendering
    TEXT_RESPONSE,  // Full-screen text response — used when TTS is disabled
};

/// Status bar data (visible in face and clock modes).
struct StatusBar {
    int8_t wifiRssi;            // Wi-Fi signal strength (-30 to -90)
    bool wifiConnected;
    bool wsConnected;
    bool connectionStalled;     // Data flow stalled during active state
    uint8_t batteryPercent;     // 0-100 or 255 = USB-powered/charging
    uint16_t batteryMv;         // raw millivolts (used to detect full charge while on USB)
    bool focusModeActive;
    bool pomodoroActive;
    uint8_t pomodoroCycle;      // 1-4
    bool blePresent;            // Phone detected nearby via BLE presence
    bool blePresenceEnabled;    // Presence scanning is active (not disabled in settings)
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
    uint8_t textSize;           // Font size multiplier (0 or 1 = default, 2 = large)
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

/// Register a callback that fires whenever the display mode changes.
/// Called with the new mode name as a C-string (e.g. "clock", "face").
/// Pass nullptr to clear. Only one callback is supported.
using ModeChangeCallback = void(*)(const char* modeName);
void setOnModeChange(ModeChangeCallback cb);

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
void setTranscriptText(const char* text);

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

/// Set the active face style by ID (0=ORBIT, 1=NOVA).
/// Takes effect immediately on the next rendered frame.
/// Call nvs_store::setFaceStyle() separately to persist across reboots.
void setFaceStyle(uint8_t styleId);

/// Returns the current face style ID.
uint8_t getFaceStyleId();

/// Override the face background, eye body, and mouth color at runtime.
///
/// bgColor      — 24-bit RGB (0xRRGGBB) for the screen background.
/// eyeBodyColor — 24-bit RGB for NOVA eye rectangles / ORBIT eye sclera.
/// mouthColor   — 24-bit RGB for the mouth shape across all expressions.
///
/// Takes effect immediately on the next rendered frame.
/// Call nvs_store::setFaceBgColor() / setFaceEyeColor() / setFaceMouthColor()
/// separately to persist across reboots.
void setFaceColors(uint32_t bgColor, uint32_t eyeBodyColor, uint32_t mouthColor);

/// Set the home mode — the mode the display returns to after wake, reminder
/// dismiss, and other events that would otherwise hard-reset to FACE.
/// Also calls setMode() to switch immediately.
void setHomeMode(Mode mode);

/// Returns the configured home mode (default: FACE).
Mode getHomeMode();

/// Show an image from the SD card on the display.
/// Supports JPEG (.jpg/.jpeg), BMP (.bmp), and PNG (.png) via LovyanGFX.
/// Image is centered on screen. Display wakes if sleeping.
/// Switches back to previous mode after durationMs (default 10s, 0 = permanent).
/// Path must be absolute from SD root, e.g. "/images/hello.jpg".
/// IMPORTANT: must only be called from the display task (Core 1 displayLoop).
/// For cross-task use, call queueImageFromSD() instead.
void showImageFromSD(const char* path, uint16_t durationMs = 10000);

/// Thread-safe: queue an image to be shown on the next display tick.
/// Use this from any task — the display task will call showImageFromSD()
/// internally, avoiding cross-task SPI/mutex conflicts with LovyanGFX.
void queueImageFromSD(const char* path, uint16_t durationMs = 10000);

/// Paint a two-bar overlay into the sprite every frame, just before the push.
/// Used by the BIOS face preview so overlay text is baked in — no flicker.
///   title   — centred in a header bar at the top
///   counter — right-aligned in the header bar  (e.g. "3/17")
///   navL/C/R — left / centre / right labels in a nav bar at the bottom
void setBiosOverlay(const char* title, const char* counter,
                    const char* navL, const char* navC, const char* navR);

/// Remove the BIOS overlay (normal face rendering resumes).
void clearBiosOverlay();

/// Append a sentence to the full-screen text response view.
/// Switches to TEXT_RESPONSE mode on first call of a new response.
/// Strips markdown before rendering.
void appendTextResponse(const char* text);

/// Mark the current text response as complete.
/// Starts an 8-second auto-return timer back to the previous mode.
void finalizeTextResponse();

/// Dismiss the text response immediately and return to the previous mode.
void clearTextResponse();

}  // namespace display
