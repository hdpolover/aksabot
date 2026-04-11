#include "touch.h"
#include "display.h"
#include "config.h"
#include "lgfx_config.h"
#include <Arduino.h>
#include <Wire.h>

// ── Configuration ──────────────────────────────────────
static const uint16_t DEBOUNCE_MS = 30;
static const uint16_t TAP_MAX_MS = 400;
static const uint16_t HOLD_THRESHOLD_MS = 300;
static const uint16_t LONG_PRESS_MS = 5000;  // 5s — avoid conflict with hold-to-talk
static const uint8_t  CONFIRM_COUNT = 2;
static const uint16_t POLL_INTERVAL_MS = 15;
static const uint16_t WAKE_COOLDOWN_MS = 500;  // Suppress touch reads after wake

// FT6336G keep-alive: periodic I2C read prevents hibernate mode.
// In hibernate the INT pin stops responding, killing tap-to-wake.
static const uint32_t KEEPALIVE_INTERVAL_MS = 3000;  // ping every 3s while sleeping

// ── LovyanGFX display instance (defined in display.cpp) ──
extern LGFX tft;

// ── Internal state ─────────────────────────────────────
static touch::EventCallback eventCb;
static bool currentlyTouched = false;
static uint32_t touchStartMs = 0;
static bool holdFired = false;
static bool longPressFired = false;

// Debounce state
static uint32_t lastPollMs = 0;
static uint32_t lastTransitionMs = 0;
static uint8_t sameStateCount = 0;
static bool pendingState = false;

// Wake cooldown
static uint32_t wakeCooldownUntil = 0;

// Boot stabilization — FT6336G needs ~300ms after reset to produce valid readings
static uint32_t bootReadyMs = 0;

// Keep-alive timer — prevents FT6336G from entering hibernate while display sleeps
static uint32_t lastKeepaliveMs = 0;

// ── Helpers ────────────────────────────────────────────

/// Read a single FT6336G register via I2C to keep the IC in Monitor mode.
/// The FT6336G transitions Active → Monitor → Hibernate when idle.
/// Any I2C transaction resets the hibernate timer, keeping INT responsive.
static void touchKeepalive() {
    Wire.beginTransmission(TOUCH_I2C_ADDR);
    Wire.write(0x00);  // register 0x00 = device mode
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)TOUCH_I2C_ADDR, (uint8_t)1);
    if (Wire.available()) Wire.read();  // discard — we just need the I2C traffic
}

static void fireEvent(touch::Event event) {
    const char* names[] = {"TAP", "HOLD_START", "HOLD_END", "LONG_PRESS", "WAKE"};
    Serial.printf("[Touch] %s\n", names[(uint8_t)event]);
    if (eventCb) {
        eventCb(event);
    }
}

static void processStateChange(bool pressed, uint32_t nowMs) {
    if (pressed && !currentlyTouched) {
        currentlyTouched = true;
        touchStartMs = nowMs;
        holdFired = false;
        longPressFired = false;

        if (display::isSleeping()) {
            fireEvent(touch::Event::WAKE);
            display::wake();
            currentlyTouched = false;
            wakeCooldownUntil = nowMs + WAKE_COOLDOWN_MS;
            return;
        }
    }
    else if (!pressed && currentlyTouched) {
        uint32_t holdDuration = nowMs - touchStartMs;
        currentlyTouched = false;

        if (holdFired) {
            // Always fire HOLD_END on release so recording stops
            fireEvent(touch::Event::HOLD_END);
        } else if (holdDuration <= TAP_MAX_MS) {
            fireEvent(touch::Event::TAP);
        }
    }
}

// ── Public API ─────────────────────────────────────────

void touch::init() {
    currentlyTouched = false;
    touchStartMs = 0;
    holdFired = false;
    longPressFired = false;
    sameStateCount = 0;
    pendingState = false;
    lastPollMs = 0;
    lastTransitionMs = 0;
    wakeCooldownUntil = 0;
    lastKeepaliveMs = 0;

    // INT pin: goes LOW when finger touches, HIGH when released
    // We read this manually to filter phantom touches from getTouch()
    pinMode(TOUCH_INT, INPUT_PULLUP);

    // FT6336G needs ~300ms after reset (done by LovyanGFX via TOUCH_RST pin)
    bootReadyMs = millis() + 500;

    Serial.println("[Touch] Using LovyanGFX Touch_FT5x06 driver");
}

void touch::onEvent(EventCallback callback) {
    eventCb = callback;
}

void touch::feedRaw(bool pressed, uint32_t nowMs) {
    processStateChange(pressed, nowMs);
}

void touch::tick(uint32_t nowMs) {
    // Poll at controlled rate
    if ((nowMs - lastPollMs) < POLL_INTERVAL_MS) goto check_hold;
    lastPollMs = nowMs;

    // Suppress reads during boot stabilization and wake cooldown
    if (nowMs < bootReadyMs) goto check_hold;
    if (nowMs < wakeCooldownUntil) goto check_hold;

    // Keep FT6336G alive while sleeping — prevent hibernate (INT pin goes dead)
    if (display::isSleeping() && (nowMs - lastKeepaliveMs) >= KEEPALIVE_INTERVAL_MS) {
        lastKeepaliveMs = nowMs;
        touchKeepalive();
    }

    {
        // Use INT pin as primary gate: LOW = finger on screen
        // This filters out FT6336G phantom touches that getTouch() can't catch
        bool intLow = (digitalRead(TOUCH_INT) == LOW);

        bool rawTouched = false;
        if (intLow) {
            if (display::isSleeping()) {
                // When sleeping, INT LOW is enough to trigger wake.
                // Skip getTouch() — FT6336G may be in standby and I2C
                // reads can fail or return stale data after long idle.
                rawTouched = true;
            } else {
                // INT says something is touching — confirm via I2C
                lgfx::touch_point_t tp;
                uint8_t count = tft.getTouch(&tp, 1);
                rawTouched = (count > 0);
            }
        }
        // If INT is HIGH, rawTouched stays false (no touch)

        // Debounce: require consecutive matching reads
        if (rawTouched != currentlyTouched) {
            if (rawTouched == pendingState) {
                sameStateCount++;
            } else {
                pendingState = rawTouched;
                sameStateCount = 1;
            }

            if (sameStateCount >= CONFIRM_COUNT &&
                (nowMs - lastTransitionMs) >= DEBOUNCE_MS) {
                lastTransitionMs = nowMs;
                sameStateCount = 0;
                processStateChange(rawTouched, nowMs);
            }
        } else {
            sameStateCount = 0;
        }
    }

check_hold:
    if (!currentlyTouched) return;

    uint32_t holdDuration = nowMs - touchStartMs;

    if (!holdFired && holdDuration >= HOLD_THRESHOLD_MS) {
        holdFired = true;
        fireEvent(Event::HOLD_START);
    }

    if (!longPressFired && holdDuration >= LONG_PRESS_MS) {
        longPressFired = true;
        fireEvent(Event::LONG_PRESS);
    }
}

bool touch::isTouched() {
    return currentlyTouched;
}

void touch::clearBootDelay() {
    bootReadyMs = 0;
    wakeCooldownUntil = 0;
}

uint32_t touch::getHoldDurationMs() {
    if (!currentlyTouched) return 0;
    return millis() - touchStartMs;
}

// ── Serial simulation (fallback) ───────────────────────

void touch::processSerial(uint32_t nowMs) {
    if (!Serial.available()) return;

    char c = Serial.read();
    switch (c) {
        case 's':
            processStateChange(true, nowMs);
            holdFired = true;
            fireEvent(Event::HOLD_START);
            break;

        case 'e':
            if (currentlyTouched) {
                processStateChange(false, nowMs);
            }
            break;

        case 'i':
            processStateChange(true, nowMs);
            processStateChange(false, nowMs + 50);
            break;

        case 'q':
            processStateChange(true, nowMs);
            longPressFired = true;
            fireEvent(Event::LONG_PRESS);
            processStateChange(false, nowMs);
            break;

        case 'w':
            if (display::isSleeping()) {
                fireEvent(Event::WAKE);
                display::wake();
            }
            break;
    }
}
