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

void presence_detector::tick(uint32_t nowMs) {
    if (currentState == PresenceState::LEAVING) {
        // Grace period: stay in LEAVING until it expires, then declare AWAY.
        // The user can still come back (feedRssi → PRESENT) within this window.
        uint32_t elapsed = nowMs - leavingStartMs;
        uint32_t graceMs = (uint32_t)cfg.gracePeriodSec * 1000;
        if (elapsed >= graceMs) {
            transition(PresenceState::AWAY, nowMs);
        }
    } else if (currentState == PresenceState::PRESENT) {
        // Time-based departure detection: if phone not seen for missingTimeoutSec,
        // start the LEAVING grace period.
        //
        // This is deliberately NOT driven by per-scan-cycle miss counts. iOS
        // background advertising pauses unpredictably (2-20s gaps). Treating a
        // missed 5-second scan window as "phone gone" causes constant flapping
        // even when the user is sitting right at the desk. The time-based check
        // is immune to per-cycle detection gaps.
        if (lastScanHitMs > 0) {
            uint32_t missingMs = (uint32_t)cfg.missingTimeoutSec * 1000;
            if ((nowMs - lastScanHitMs) >= missingMs) {
                leavingStartMs = nowMs;
                transition(PresenceState::LEAVING, nowMs);
            }
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
        default:
            // Use the same full scan interval for PRESENT, LEAVING, and UNKNOWN.
            // Halving the interval during LEAVING makes detections less reliable
            // (shorter windows = fewer chances to catch iOS background advertising),
            // which is the opposite of what we want. The 45s grace period already
            // gives plenty of time to re-detect before transitioning to AWAY.
            return cfg.scanIntervalMs;
    }
}

void presence_detector::updateConfig(const Config& config) {
    cfg = config;
    if (cfg.rssiWindowSize > MAX_WINDOW) cfg.rssiWindowSize = MAX_WINDOW;

    // Reset RSSI window and hit timestamp so the new timeout starts fresh
    rssiCount    = 0;
    rssiIndex    = 0;
    rssiSum      = 0;
    lastScanHitMs = 0;

    Serial.printf("[Presence] Config updated — threshold=%ddBm, grace=%us, timeout=%us\n",
        cfg.rssiThreshold, cfg.gracePeriodSec, cfg.missingTimeoutSec);
}
