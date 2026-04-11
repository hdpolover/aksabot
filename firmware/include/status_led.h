#pragma once
#include "state.h"
#include <cstdint>

/// RGB status LED controller (WS2812B on GPIO42).
///
/// Maps BotState + connectivity to LED color/pattern. Runs non-blocking
/// animations (breathe, pulse, blink) inside tick().
///
/// Color mapping:
///   Idle + connected     → green slow breathe
///   Listening            → blue solid
///   Thinking             → yellow pulse
///   Speaking             → cyan solid
///   Focus mode           → purple dim solid
///   Offline/disconnected → red slow blink
///   Low battery          → orange fast blink
///   Sleeping             → off
///   OTA in progress      → white fast pulse
namespace status_led {

/// LED animation patterns.
enum class Pattern : uint8_t {
    SOLID,      // Constant color
    BREATHE,    // Smooth sine wave brightness cycle
    PULSE,      // Faster breathe
    BLINK,      // On/off toggle
    FAST_BLINK, // Rapid on/off
    OFF,        // LED completely off
};

/// Initialize the WS2812B LED.
void init();

/// Advance animation. Call from loop() or a task (~30fps is fine).
void tick(uint32_t nowMs);

/// Automatically set LED based on current BotState and AppState.
/// Call whenever state changes.
void syncToState();

/// Override LED with a specific color and pattern.
/// Lasts until the next syncToState() call.
void set(uint8_t r, uint8_t g, uint8_t b, Pattern pattern = Pattern::SOLID);

/// Override: low battery warning.
void showLowBattery();

/// Override: OTA in progress.
void showOta();

/// Override: focus mode.
void showFocusMode();

/// Turn LED off.
void off();

}  // namespace status_led
