#include "touch.h"
#include "display.h"
#include <Arduino.h>

// ── Configuration ──────────────────────────────────────
static const uint16_t DEBOUNCE_MS = 30;
static const uint16_t TAP_MAX_MS = 300;
static const uint16_t HOLD_THRESHOLD_MS = 300;
static const uint16_t LONG_PRESS_MS = 3000;

// ── Internal state ─────────────────────────────────────
static touch::EventCallback eventCb;
static bool currentlyTouched = false;
static uint32_t touchStartMs = 0;
static uint32_t lastRawChangeMs = 0;
static bool lastRawState = false;
static bool holdFired = false;
static bool longPressFired = false;

// ── Helpers ────────────────────────────────────────────

static void fireEvent(touch::Event event) {
    Serial.printf("[Touch] Event: %u\n", (uint8_t)event);
    if (eventCb) {
        eventCb(event);
    }
}

// ── Public API ─────────────────────────────────────────

void touch::init() {
    currentlyTouched = false;
    touchStartMs = 0;
    holdFired = false;
    longPressFired = false;

    // TODO: Initialize capacitive touch controller over SPI
    // For now, touch input comes from serial simulation.

    Serial.println("[Touch] Initialized (serial simulation active)");
}

void touch::onEvent(EventCallback callback) {
    eventCb = callback;
}

void touch::feedRaw(bool pressed, uint32_t nowMs) {
    // Debounce
    if (pressed == lastRawState && (nowMs - lastRawChangeMs) < DEBOUNCE_MS) {
        return;
    }
    lastRawState = pressed;
    lastRawChangeMs = nowMs;

    if (pressed && !currentlyTouched) {
        // Touch start
        currentlyTouched = true;
        touchStartMs = nowMs;
        holdFired = false;
        longPressFired = false;

        // If display is sleeping, wake instead of starting interaction
        if (display::isSleeping()) {
            fireEvent(Event::WAKE);
            display::wake();
            // Consume this touch — don't also start recording
            currentlyTouched = false;
            return;
        }
    }
    else if (!pressed && currentlyTouched) {
        // Touch end
        uint32_t holdDuration = nowMs - touchStartMs;
        currentlyTouched = false;

        if (longPressFired) {
            // Long press already handled
        } else if (holdFired) {
            fireEvent(Event::HOLD_END);
        } else if (holdDuration < TAP_MAX_MS) {
            fireEvent(Event::TAP);
        } else {
            // Held past tap threshold but never crossed hold threshold
            // (shouldn't happen with current thresholds but handle gracefully)
            fireEvent(Event::TAP);
        }
    }
}

void touch::tick(uint32_t nowMs) {
    if (!currentlyTouched) return;

    uint32_t holdDuration = nowMs - touchStartMs;

    // Check for hold start
    if (!holdFired && holdDuration >= HOLD_THRESHOLD_MS) {
        holdFired = true;
        fireEvent(Event::HOLD_START);
    }

    // Check for long press
    if (!longPressFired && holdDuration >= LONG_PRESS_MS) {
        longPressFired = true;
        fireEvent(Event::LONG_PRESS);
    }
}

bool touch::isTouched() {
    return currentlyTouched;
}

uint32_t touch::getHoldDurationMs() {
    if (!currentlyTouched) return 0;
    return millis() - touchStartMs;
}

// ── Serial simulation ──────────────────────────────────

void touch::processSerial(uint32_t nowMs) {
    if (!Serial.available()) return;

    char c = Serial.read();
    switch (c) {
        case 's':  // Simulate touch press (start recording)
            feedRaw(true, nowMs);
            // Auto-fire hold after threshold for convenience
            holdFired = true;
            fireEvent(Event::HOLD_START);
            Serial.println("[Touch] Serial: press (hold start)");
            break;

        case 'e':  // Simulate touch release (stop recording)
            if (currentlyTouched) {
                feedRaw(false, nowMs);
                Serial.println("[Touch] Serial: release");
            }
            break;

        case 'i':  // Simulate quick tap (interrupt)
            feedRaw(true, nowMs);
            feedRaw(false, nowMs + 50);  // Instant release = tap
            Serial.println("[Touch] Serial: tap (interrupt)");
            break;

        case 'q':  // Simulate long press (end session)
            feedRaw(true, nowMs);
            longPressFired = true;
            fireEvent(Event::LONG_PRESS);
            feedRaw(false, nowMs);
            Serial.println("[Touch] Serial: long press (end session)");
            break;

        case 'w':  // Simulate wake
            if (display::isSleeping()) {
                fireEvent(Event::WAKE);
                display::wake();
                Serial.println("[Touch] Serial: wake");
            }
            break;
    }
}
