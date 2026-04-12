#include "presence_detector.h"
#include "state.h"
#include <Arduino.h>

// ── Internal state ─────────────────────────────────────
static presence_detector::Config cfg;
static presence_detector::StateChangeCallback changeCb;

static PresenceState currentState = PresenceState::UNKNOWN;

// RSSI rolling average
static const uint8_t MAX_WINDOW = 10;
static int8_t rssiWindow[MAX_WINDOW];
static uint8_t rssiCount = 0;
static uint8_t rssiIndex = 0;
static int16_t rssiSum = 0;

// Timing
static uint32_t leavingStartMs = 0;     // When LEAVING state began
static uint32_t lastPresentMs = 0;      // Last time state was PRESENT
static uint32_t lastScanHitMs = 0;      // Last time target was found in scan

// ── Helpers ────────────────────────────────────────────

static int8_t computeSmoothedRssi() {
    if (rssiCount == 0) return -127;  // no data
    return (int8_t)(rssiSum / rssiCount);
}

static void transition(PresenceState newState, uint32_t nowMs) {
    if (newState == currentState) return;

    PresenceState oldState = currentState;
    currentState = newState;
    appState.presenceState = newState;

    uint32_t awayDuration = 0;
    if (oldState == PresenceState::AWAY && lastPresentMs > 0) {
        awayDuration = (nowMs - lastPresentMs) / 1000;
    }

    if (newState == PresenceState::PRESENT) {
        lastPresentMs = nowMs;
    }

    Serial.printf("[Presence] %s → %s (away %us)\n",
        oldState == PresenceState::UNKNOWN  ? "UNKNOWN" :
        oldState == PresenceState::PRESENT  ? "PRESENT" :
        oldState == PresenceState::LEAVING  ? "LEAVING" : "AWAY",
        newState == PresenceState::PRESENT  ? "PRESENT" :
        newState == PresenceState::LEAVING  ? "LEAVING" : "AWAY",
        awayDuration);

    if (changeCb) {
        changeCb(newState, oldState, awayDuration);
    }
}

// ── Public API ─────────────────────────────────────────

void presence_detector::init(const Config& config) {
    cfg = config;
    if (cfg.rssiWindowSize > MAX_WINDOW) cfg.rssiWindowSize = MAX_WINDOW;

    currentState = PresenceState::UNKNOWN;
    appState.presenceState = PresenceState::UNKNOWN;
    rssiCount = 0;
    rssiIndex = 0;
    rssiSum = 0;
    leavingStartMs = 0;
    lastPresentMs = 0;
    lastScanHitMs = 0;

    Serial.printf("[Presence] Init — threshold=%ddBm, grace=%us, window=%u\n",
        cfg.rssiThreshold, cfg.gracePeriodSec, cfg.rssiWindowSize);
}

void presence_detector::onStateChange(StateChangeCallback callback) {
    changeCb = callback;
}

void presence_detector::feedRssi(int8_t rssi) {
    uint32_t now = millis();
    lastScanHitMs = now;

    // Update rolling average
    if (rssiCount < cfg.rssiWindowSize) {
        rssiWindow[rssiIndex] = rssi;
        rssiSum += rssi;
        rssiCount++;
    } else {
        rssiSum -= rssiWindow[rssiIndex];
        rssiWindow[rssiIndex] = rssi;
        rssiSum += rssi;
    }
    rssiIndex = (rssiIndex + 1) % cfg.rssiWindowSize;

    int8_t smoothed = computeSmoothedRssi();

    // Entry threshold: become PRESENT if signal is strong enough.
    // Leave threshold: only start LEAVING once signal drops hysteresisDb below
    // the entry threshold, preventing flapping when RSSI hovers near the edge.
    int8_t leaveThreshold = cfg.rssiThreshold - cfg.hysteresisDb;

    if (smoothed >= cfg.rssiThreshold) {
        // Signal is strong enough — user is present
        if (currentState != PresenceState::PRESENT) {
            transition(PresenceState::PRESENT, now);
        }
    } else if (smoothed < leaveThreshold) {
        // Signal has dropped well below threshold — start leaving
        if (currentState == PresenceState::PRESENT) {
            leavingStartMs = now;
            transition(PresenceState::LEAVING, now);
        }
        // If UNKNOWN, transition to LEAVING to start grace timer
        if (currentState == PresenceState::UNKNOWN) {
            leavingStartMs = now;
            transition(PresenceState::LEAVING, now);
        }
        // If LEAVING, grace period is checked in tick()
    }
    // If smoothed is between leaveThreshold and rssiThreshold (the hysteresis
    // band), hold the current state — no transition in either direction.
}

void presence_detector::feedMiss() {
    uint32_t now = millis();

    // Target not found in scan
    switch (currentState) {
        case PresenceState::PRESENT:
            // Start grace period
            leavingStartMs = now;
            transition(PresenceState::LEAVING, now);
            break;

        case PresenceState::UNKNOWN:
            // No device ever seen — stay unknown until first sighting
            break;

        case PresenceState::LEAVING:
        case PresenceState::AWAY:
            // Already transitioning or away — tick() handles the rest
            break;
    }
}

void presence_detector::tick(uint32_t nowMs) {
    if (currentState == PresenceState::LEAVING) {
        uint32_t elapsed = nowMs - leavingStartMs;
        uint32_t graceMs = (uint32_t)cfg.gracePeriodSec * 1000;

        if (elapsed >= graceMs) {
            transition(PresenceState::AWAY, nowMs);
        }
    }
}

PresenceState presence_detector::getState() {
    return currentState;
}

int8_t presence_detector::getSmoothedRssi() {
    return computeSmoothedRssi();
}

uint32_t presence_detector::getAwayDurationSec() {
    if (currentState == PresenceState::PRESENT || lastPresentMs == 0) return 0;
    return (millis() - lastPresentMs) / 1000;
}

uint32_t presence_detector::getRecommendedScanIntervalMs() {
    switch (currentState) {
        case PresenceState::AWAY:
            return cfg.awayScanIntervalMs;
        case PresenceState::LEAVING:
            return cfg.scanIntervalMs / 2;  // Scan faster during grace period
        default:
            return cfg.scanIntervalMs;
    }
}

void presence_detector::updateConfig(const Config& config) {
    cfg = config;
    if (cfg.rssiWindowSize > MAX_WINDOW) cfg.rssiWindowSize = MAX_WINDOW;

    // Reset RSSI window on config change
    rssiCount = 0;
    rssiIndex = 0;
    rssiSum = 0;

    Serial.printf("[Presence] Config updated — threshold=%ddBm, grace=%us\n",
        cfg.rssiThreshold, cfg.gracePeriodSec);
}
