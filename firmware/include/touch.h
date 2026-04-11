#pragma once
#include <cstdint>
#include <functional>

/// Touch input abstraction layer.
///
/// Processes raw touch events into higher-level gestures:
/// tap-to-talk, interrupt, wake, long press, dismiss.
///
/// The hardware driver calls touch::feedRaw() with press/release events.
/// The touch module debounces, detects hold duration, and fires callbacks.
namespace touch {

/// Touch event types.
enum class Event : uint8_t {
    TAP,            // Quick tap (< 300ms)
    HOLD_START,     // Touch began and held past hold threshold
    HOLD_END,       // Touch released after hold
    LONG_PRESS,     // Held for 3+ seconds
    WAKE,           // Touch while sleeping — just wake, don't act
};

/// Callback type for touch events.
using EventCallback = std::function<void(Event event)>;

/// Initialize touch system.
void init();

/// Register callback for touch events.
void onEvent(EventCallback callback);

/// Feed a raw touch event from the hardware driver.
/// pressed=true when finger touches, pressed=false when released.
void feedRaw(bool pressed, uint32_t nowMs);

/// Advance timers (call from loop/task, handles hold→long_press transition).
void tick(uint32_t nowMs);

/// Check if currently being touched.
bool isTouched();

/// Clear the boot stabilization delay (for BIOS menu entry).
void clearBootDelay();

/// Get how long the current touch has been held (ms). 0 if not touching.
uint32_t getHoldDurationMs();

// ── Serial simulation (Phase 1) ────────────────────

/// Process serial input for touch simulation.
/// 's'=press, 'e'=release, 'i'=tap (interrupt), 'q'=long press.
void processSerial(uint32_t nowMs);

}  // namespace touch
