#include "power_manager.h"
#include "display.h"
#include <Arduino.h>

// ── Internal state ─────────────────────────────────────
static power_manager::Config cfg;
static power_manager::PowerState currentState = power_manager::PowerState::ACTIVE;
static uint32_t lastInteractionMs = 0;
static bool initialized = false;

// ── Public API ─────────────────────────────────────────

void power_manager::init(const Config& config) {
    cfg = config;
    currentState = PowerState::ACTIVE;
    lastInteractionMs = millis();
    initialized = true;

    display::setBrightness(cfg.activeBrightness);
    Serial.printf("[Power] Init — dim=%us, sleep=%us\n",
        cfg.dimTimeoutSec, cfg.sleepTimeoutSec);
}

void power_manager::recordInteraction() {
    lastInteractionMs = millis();

    if (currentState != PowerState::ACTIVE) {
        PowerState prev = currentState;
        currentState = PowerState::ACTIVE;

        if (prev == PowerState::SLEEPING) {
            display::wake();
        }
        display::setBrightness(cfg.activeBrightness);

        Serial.printf("[Power] Wake → ACTIVE (was %s)\n",
            prev == PowerState::DIM ? "DIM" : "SLEEPING");
    }
}

void power_manager::tick(uint32_t nowMs) {
    if (!initialized) return;

    // Guard against underflow: recordInteraction() calls millis() which can be
    // newer than the nowMs snapshot passed from the main loop
    if (nowMs < lastInteractionMs) return;
    uint32_t idleMs = nowMs - lastInteractionMs;
    uint32_t idleSec = idleMs / 1000;

    switch (currentState) {
        case PowerState::ACTIVE:
            if (idleSec >= cfg.sleepTimeoutSec) {
                currentState = PowerState::SLEEPING;
                display::sleep();
                Serial.println("[Power] ACTIVE → SLEEPING");
            } else if (idleSec >= cfg.dimTimeoutSec) {
                currentState = PowerState::DIM;
                display::setBrightness(cfg.dimBrightness);
                Serial.println("[Power] ACTIVE → DIM");
            }
            break;

        case PowerState::DIM:
            if (idleSec >= cfg.sleepTimeoutSec) {
                currentState = PowerState::SLEEPING;
                display::sleep();
                Serial.println("[Power] DIM → SLEEPING");
            }
            break;

        case PowerState::SLEEPING:
            // Stay sleeping until recordInteraction() or setState()
            break;
    }
}

power_manager::PowerState power_manager::getState() {
    return currentState;
}

void power_manager::setState(PowerState state) {
    if (state == currentState) return;

    currentState = state;
    switch (state) {
        case PowerState::ACTIVE:
            display::wake();
            display::setBrightness(cfg.activeBrightness);
            lastInteractionMs = millis();
            break;
        case PowerState::DIM:
            display::setBrightness(cfg.dimBrightness);
            break;
        case PowerState::SLEEPING:
            display::sleep();
            break;
    }
}

void power_manager::updateConfig(const Config& config) {
    cfg = config;
    if (currentState == PowerState::ACTIVE) {
        display::setBrightness(cfg.activeBrightness);
    } else if (currentState == PowerState::DIM) {
        display::setBrightness(cfg.dimBrightness);
    }
}

uint32_t power_manager::getIdleSeconds() {
    return (millis() - lastInteractionMs) / 1000;
}
