#include "touch.h"
#include "display.h"
#include "config.h"
#include <Wire.h>
#include <Arduino.h>

// ── Configuration ──────────────────────────────────────
static const uint16_t DEBOUNCE_MS = 30;
static const uint16_t TAP_MAX_MS = 300;
static const uint16_t HOLD_THRESHOLD_MS = 300;
static const uint16_t LONG_PRESS_MS = 3000;

// ── FT6336G I2C Touch Driver ──────────────────────────
// Register addresses for FT6336G capacitive touch IC
static const uint8_t FT_REG_NUM_TOUCHES = 0x02;
static const uint8_t FT_REG_TOUCH1_XH   = 0x03;
static const uint8_t FT_REG_TOUCH1_XL   = 0x04;
static const uint8_t FT_REG_TOUCH1_YH   = 0x05;
static const uint8_t FT_REG_TOUCH1_YL   = 0x06;
static const uint8_t FT_I2C_ADDR        = TOUCH_I2C_ADDR;

static TwoWire touchWire(0);  // I2C bus 0 for touch
static bool hwInitialized = false;

// Read a register from the touch IC
static uint8_t ft_readReg(uint8_t reg) {
    touchWire.beginTransmission(FT_I2C_ADDR);
    touchWire.write(reg);
    touchWire.endTransmission(false);
    touchWire.requestFrom((uint8_t)FT_I2C_ADDR, (uint8_t)1);
    if (touchWire.available()) {
        return touchWire.read();
    }
    return 0;
}

// Poll touch state from hardware
static bool ft_isTouched() {
    if (!hwInitialized) return false;
    uint8_t numTouches = ft_readReg(FT_REG_NUM_TOUCHES);
    return (numTouches > 0 && numTouches < 5);
}

// ── Internal state ─────────────────────────────────────
static touch::EventCallback eventCb;
static bool currentlyTouched = false;
static uint32_t touchStartMs = 0;
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

    // Initialize I2C for FT6336G touch controller
    touchWire.begin(TOUCH_SDA, TOUCH_SCL, 400000);

    // Reset touch IC
    pinMode(TOUCH_RST, OUTPUT);
    digitalWrite(TOUCH_RST, LOW);
    delay(10);
    digitalWrite(TOUCH_RST, HIGH);
    delay(100);

    // Configure interrupt pin
    pinMode(TOUCH_INT, INPUT_PULLUP);

    // Verify touch IC is responding
    touchWire.beginTransmission(FT_I2C_ADDR);
    uint8_t err = touchWire.endTransmission();
    if (err == 0) {
        hwInitialized = true;
        Serial.println("[Touch] FT6336G initialized (I2C)");
    } else {
        Serial.printf("[Touch] FT6336G not found at 0x%02X (err=%d), using serial simulation\n",
            FT_I2C_ADDR, err);
    }
}

void touch::onEvent(EventCallback callback) {
    eventCb = callback;
}

void touch::feedRaw(bool pressed, uint32_t nowMs) {
    if (pressed && !currentlyTouched) {
        currentlyTouched = true;
        touchStartMs = nowMs;
        holdFired = false;
        longPressFired = false;

        if (display::isSleeping()) {
            fireEvent(Event::WAKE);
            display::wake();
            currentlyTouched = false;
            return;
        }
    }
    else if (!pressed && currentlyTouched) {
        uint32_t holdDuration = nowMs - touchStartMs;
        currentlyTouched = false;

        if (longPressFired) {
            // Already handled
        } else if (holdFired) {
            fireEvent(Event::HOLD_END);
        } else if (holdDuration < TAP_MAX_MS) {
            fireEvent(Event::TAP);
        } else {
            fireEvent(Event::TAP);
        }
    }
}

void touch::tick(uint32_t nowMs) {
    // Poll hardware touch if available
    if (hwInitialized) {
        bool touched = ft_isTouched();
        if (touched != currentlyTouched) {
            feedRaw(touched, nowMs);
        }
    }

    // Check for hold/long press transitions
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
            feedRaw(true, nowMs);
            holdFired = true;
            fireEvent(Event::HOLD_START);
            break;

        case 'e':
            if (currentlyTouched) {
                feedRaw(false, nowMs);
            }
            break;

        case 'i':
            feedRaw(true, nowMs);
            feedRaw(false, nowMs + 50);
            break;

        case 'q':
            feedRaw(true, nowMs);
            longPressFired = true;
            fireEvent(Event::LONG_PRESS);
            feedRaw(false, nowMs);
            break;

        case 'w':
            if (display::isSleeping()) {
                fireEvent(Event::WAKE);
                display::wake();
            }
            break;
    }
}
