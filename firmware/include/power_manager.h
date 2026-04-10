#pragma once
#include <cstdint>

/// Power management state machine.
///
/// Manages display dimming, sleep/wake transitions, and BLE scan
/// duty cycle based on user interaction and presence detection.
///
/// States:
///   ACTIVE  — full brightness, all systems on
///   DIM     — reduced brightness, all systems on
///   SLEEP   — display off, mic off, Wi-Fi low-power, BLE scan reduced
///
/// Transitions:
///   ACTIVE → DIM   after dimTimeoutSec of no interaction
///   DIM    → SLEEP after sleepTimeoutSec of no interaction
///   SLEEP  → ACTIVE on touch, presence PRESENT, or WebSocket event
///   Any    → ACTIVE on user interaction (touch, voice)
namespace power_manager {

/// Power states.
enum class PowerState : uint8_t {
    ACTIVE,
    DIM,
    SLEEPING,
};

/// Configuration.
struct Config {
    uint16_t dimTimeoutSec = 30;        // Seconds idle before dimming
    uint16_t sleepTimeoutSec = 300;     // Seconds idle before sleep (5 min)
    uint8_t dimBrightness = 30;         // Display brightness in DIM state (0-100)
    uint8_t activeBrightness = 70;      // Display brightness in ACTIVE state
};

/// Initialize power management.
void init(const Config& config = Config{});

/// Record a user interaction (touch, voice, etc.).
/// Resets idle timer and transitions to ACTIVE if not already.
void recordInteraction();

/// Advance timers. Call from main loop.
void tick(uint32_t nowMs);

/// Get current power state.
PowerState getState();

/// Force a specific power state (e.g., from presence detector).
void setState(PowerState state);

/// Update configuration at runtime.
void updateConfig(const Config& config);

/// Get seconds since last interaction.
uint32_t getIdleSeconds();

}  // namespace power_manager
