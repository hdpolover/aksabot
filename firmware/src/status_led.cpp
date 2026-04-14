#include "status_led.h"
#include "config.h"
#include "state.h"
#include "power_manager.h"
#include <FastLED.h>

// ── LED hardware ──────────────────────────────────────
static CRGB leds[LED_COUNT];

// ── Animation state ───────────────────────────────────
static uint8_t targetR = 0, targetG = 0, targetB = 0;
static status_led::Pattern currentPattern = status_led::Pattern::OFF;
static uint32_t animStartMs = 0;
static bool overrideActive = false;

// Animation timing (ms)
static const uint16_t BREATHE_PERIOD   = 3000;
static const uint16_t PULSE_PERIOD     = 1000;
static const uint16_t BLINK_PERIOD     = 1500;
static const uint16_t FAST_BLINK_PERIOD = 400;

// Max brightness (0-255) — keep low, this is a status indicator not a flashlight
static const uint8_t MAX_BRIGHTNESS = 40;

// ── Helpers ───────────────────────────────────────────

static uint8_t breatheCurve(uint32_t elapsed, uint16_t period) {
    // Sine-based breathe: 0 → MAX → 0
    float phase = (float)(elapsed % period) / (float)period;
    float val = sinf(phase * 2.0f * 3.14159f);
    // Map [-1, 1] to [0, 1]
    val = (val + 1.0f) * 0.5f;
    // Apply minimum floor so it never fully goes dark
    return (uint8_t)(val * MAX_BRIGHTNESS * 0.9f + MAX_BRIGHTNESS * 0.1f);
}

static uint8_t blinkCurve(uint32_t elapsed, uint16_t period) {
    return ((elapsed % period) < (period / 2)) ? MAX_BRIGHTNESS : 0;
}

// ── Public API ────────────────────────────────────────

void status_led::init() {
    FastLED.addLeds<WS2812B, LED_PIN, GRB>(leds, LED_COUNT);
    FastLED.setBrightness(MAX_BRIGHTNESS);
    leds[0] = CRGB::Black;
    FastLED.show();

    Serial.println("[LED] Status LED initialized (GPIO42)");
}

void status_led::tick(uint32_t nowMs) {
    if (currentPattern == Pattern::OFF) {
        leds[0] = CRGB::Black;
        FastLED.show();
        return;
    }

    uint32_t elapsed = nowMs - animStartMs;
    uint8_t bright;

    switch (currentPattern) {
        case Pattern::SOLID:
            bright = MAX_BRIGHTNESS;
            break;
        case Pattern::BREATHE:
            bright = breatheCurve(elapsed, BREATHE_PERIOD);
            break;
        case Pattern::PULSE:
            bright = breatheCurve(elapsed, PULSE_PERIOD);
            break;
        case Pattern::BLINK:
            bright = blinkCurve(elapsed, BLINK_PERIOD);
            break;
        case Pattern::FAST_BLINK:
            bright = blinkCurve(elapsed, FAST_BLINK_PERIOD);
            break;
        default:
            bright = 0;
            break;
    }

    // Scale color by brightness
    leds[0].r = (uint8_t)((uint16_t)targetR * bright / 255);
    leds[0].g = (uint8_t)((uint16_t)targetG * bright / 255);
    leds[0].b = (uint8_t)((uint16_t)targetB * bright / 255);
    FastLED.show();
}

void status_led::syncToState() {
    if (overrideActive) return;

    BotState bot = appState.botState;
    bool connected = appState.wifiConnected && appState.wsConnected;

    // Power state takes priority for sleeping
    if (bot == BotState::SLEEPING ||
        power_manager::getState() == power_manager::PowerState::SLEEPING) {
        off();
        return;
    }

    switch (bot) {
        case BotState::IDLE:
            if (connected) {
                set(0, 200, 80, Pattern::BREATHE);    // Green breathe
            } else if (appState.wifiConnected) {
                set(200, 160, 0, Pattern::BREATHE);    // Yellow breathe (WiFi ok, no WS)
            } else {
                set(200, 40, 40, Pattern::BLINK);      // Red blink (no WiFi)
            }
            break;

        case BotState::LISTENING:
            set(30, 100, 255, Pattern::SOLID);         // Blue solid
            break;

        case BotState::THINKING:
            set(255, 180, 30, Pattern::PULSE);         // Yellow/amber pulse
            break;

        case BotState::SPEAKING:
            set(0, 200, 220, Pattern::SOLID);          // Cyan solid
            break;

        case BotState::INTERCOM:
            set(200, 50, 180, Pattern::PULSE);         // Magenta pulse — incoming voice from app
            break;

        case BotState::OFFLINE:
            set(200, 40, 40, Pattern::BLINK);          // Red slow blink
            break;

        case BotState::SLEEPING:
            off();
            break;
    }
}

void status_led::set(uint8_t r, uint8_t g, uint8_t b, Pattern pattern) {
    targetR = r;
    targetG = g;
    targetB = b;
    currentPattern = pattern;
    animStartMs = millis();
    overrideActive = false;
}

void status_led::showLowBattery() {
    targetR = 255;
    targetG = 120;
    targetB = 0;
    currentPattern = Pattern::FAST_BLINK;
    animStartMs = millis();
    overrideActive = true;
}

void status_led::showOta() {
    targetR = 255;
    targetG = 255;
    targetB = 255;
    currentPattern = Pattern::PULSE;
    animStartMs = millis();
    overrideActive = true;
}

void status_led::showFocusMode() {
    targetR = 140;
    targetG = 60;
    targetB = 200;
    currentPattern = Pattern::SOLID;
    animStartMs = millis();
    overrideActive = true;
}

void status_led::off() {
    currentPattern = Pattern::OFF;
    overrideActive = false;
    leds[0] = CRGB::Black;
    FastLED.show();
}
