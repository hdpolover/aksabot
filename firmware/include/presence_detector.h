#pragma once
#include "state.h"
#include <cstdint>
#include <functional>

/// BLE presence detection module.
///
/// Detects whether the user's phone is nearby by scanning for a known
/// BLE service UUID (0xFFE4) advertised by the Flutter app.
///
/// State machine:
///   UNKNOWN → PRESENT  (RSSI above threshold)
///   PRESENT → LEAVING  (RSSI drops below threshold)
///   LEAVING → PRESENT  (RSSI recovers within grace period)
///   LEAVING → AWAY     (grace period expires)
///   AWAY    → PRESENT  (RSSI above threshold — triggers greeting)
///
/// The actual BLE scanning is hardware-dependent and will be wired in
/// when the ESP32 is available. This module implements the pure state
/// machine logic that processes RSSI readings.
namespace presence_detector {

/// Callback fired on state transitions.
/// Parameters: (new_state, old_state, away_duration_seconds)
using StateChangeCallback = std::function<void(PresenceState, PresenceState, uint32_t)>;

/// Configuration for the presence detector.
struct Config {
    int8_t rssiThreshold = -75;       // dBm — below this = not present
    uint8_t gracePeriodSec = 45;      // Seconds in LEAVING before transitioning to AWAY
    uint8_t rssiWindowSize = 5;       // Number of readings for rolling average
    uint32_t scanIntervalMs = 5000;   // How often to scan (ms)
    uint32_t awayScanIntervalMs = 30000; // Scan interval when AWAY (power saving)
};

/// Initialize the presence detector with configuration.
void init(const Config& config);

/// Register a callback for state changes.
void onStateChange(StateChangeCallback callback);

/// Feed a new RSSI reading. Call this each time a BLE scan finds the target.
/// The state machine will update based on the smoothed RSSI value.
void feedRssi(int8_t rssi);

/// Call this when a scan completes and the target was NOT found.
/// Advances the grace period timer when in PRESENT/LEAVING state.
void feedMiss();

/// Must be called periodically (e.g., from loop or a task) to advance
/// the grace period timer. Pass current millis().
void tick(uint32_t nowMs);

/// Get the current presence state.
PresenceState getState();

/// Get the smoothed RSSI (rolling average of last N readings).
int8_t getSmoothedRssi();

/// Get seconds since the user was last PRESENT (0 if currently present).
uint32_t getAwayDurationSec();

/// Get the recommended scan interval based on current state.
uint32_t getRecommendedScanIntervalMs();

/// Update configuration at runtime (e.g., from BLE settings write).
void updateConfig(const Config& config);

}  // namespace presence_detector
