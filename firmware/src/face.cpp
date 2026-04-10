#include "face.h"
#include <Arduino.h>
#include <cstdlib>

// ── Internal state ─────────────────────────────────────
static face::FaceState state;
static face::Expression targetExpr = face::Expression::IDLE;

// Blink timing
static uint32_t nextBlinkMs = 0;
static uint32_t blinkStartMs = 0;
static const uint16_t BLINK_DURATION_MS = 150;
static const uint16_t BLINK_MIN_INTERVAL_MS = 3000;
static const uint16_t BLINK_MAX_INTERVAL_MS = 8000;
static bool isBlinking = false;

// Transition
static uint32_t transitionStartMs = 0;
static uint16_t transitionDurationMs = 200;
static face::Expression transitionFromExpr = face::Expression::IDLE;

// Thinking animation
static uint32_t lastThinkingDotMs = 0;
static const uint16_t THINKING_DOT_INTERVAL_MS = 400;

// Breathing (sleeping)
static const uint16_t BREATH_CYCLE_MS = 4000;  // Full in-out cycle

// Speaking
static float currentAmplitude = 0.0f;
static float smoothedAmplitude = 0.0f;

// ── Helpers ────────────────────────────────────────────

static void scheduleNextBlink(uint32_t nowMs) {
    uint16_t interval = BLINK_MIN_INTERVAL_MS +
        (rand() % (BLINK_MAX_INTERVAL_MS - BLINK_MIN_INTERVAL_MS));
    nextBlinkMs = nowMs + interval;
}

static bool shouldBlink(face::Expression expr) {
    // Only blink in idle-like states
    return expr == face::Expression::IDLE ||
           expr == face::Expression::ENCOURAGING ||
           expr == face::Expression::CALM ||
           expr == face::Expression::FOCUSED ||
           expr == face::Expression::SPEAKING;
}

// ── Public API ─────────────────────────────────────────

void face::init() {
    state.expression = Expression::IDLE;
    state.eyesOpen = true;
    state.mouthOpenness = 0.0f;
    state.breathPhase = 0.0f;
    state.thinkingDotCount = 0;
    state.transitionActive = false;
    state.transitionProgress = 0.0f;

    targetExpr = Expression::IDLE;
    scheduleNextBlink(millis());

    Serial.println("[Face] Initialized");
}

void face::tick(uint32_t nowMs) {
    // ── Transition handling ─────────────────────────
    if (state.transitionActive) {
        uint32_t elapsed = nowMs - transitionStartMs;
        if (elapsed >= transitionDurationMs) {
            state.transitionActive = false;
            state.transitionProgress = 1.0f;
            state.expression = targetExpr;
        } else {
            state.transitionProgress = (float)elapsed / transitionDurationMs;
        }
    }

    face::Expression activeExpr = state.transitionActive ? targetExpr : state.expression;

    // ── Blink handling ──────────────────────────────
    if (shouldBlink(activeExpr)) {
        if (isBlinking) {
            if ((nowMs - blinkStartMs) >= BLINK_DURATION_MS) {
                isBlinking = false;
                state.eyesOpen = true;
                scheduleNextBlink(nowMs);
            }
        } else if (nowMs >= nextBlinkMs) {
            isBlinking = true;
            blinkStartMs = nowMs;
            state.eyesOpen = false;
        } else {
            state.eyesOpen = true;
        }
    } else if (activeExpr == face::Expression::SLEEPING) {
        state.eyesOpen = false;
    } else {
        state.eyesOpen = true;
    }

    // ── Expression-specific animations ──────────────

    switch (activeExpr) {
        case Expression::THINKING:
            // Cycling dots: 0 → 1 → 2 → 3 → 0...
            if ((nowMs - lastThinkingDotMs) >= THINKING_DOT_INTERVAL_MS) {
                state.thinkingDotCount = (state.thinkingDotCount + 1) % 4;
                lastThinkingDotMs = nowMs;
            }
            state.mouthOpenness = 0.0f;
            break;

        case Expression::SPEAKING:
            // Smooth the amplitude for natural mouth movement
            smoothedAmplitude += (currentAmplitude - smoothedAmplitude) * 0.3f;
            state.mouthOpenness = smoothedAmplitude;
            break;

        case Expression::SLEEPING:
            // Breathing cycle: sine wave 0→1→0
            {
                uint32_t phase = nowMs % BREATH_CYCLE_MS;
                float t = (float)phase / BREATH_CYCLE_MS;
                // Sine approximation for smooth breathing
                state.breathPhase = 0.5f + 0.5f * sinf(t * 2.0f * 3.14159f);
            }
            state.mouthOpenness = 0.0f;
            break;

        default:
            state.mouthOpenness = 0.0f;
            state.thinkingDotCount = 0;
            state.breathPhase = 0.0f;
            break;
    }
}

void face::setExpression(Expression expr, uint16_t transitionMs) {
    if (expr == targetExpr && !state.transitionActive) return;

    transitionFromExpr = state.expression;
    targetExpr = expr;

    if (transitionMs == 0) {
        state.expression = expr;
        state.transitionActive = false;
    } else {
        state.transitionActive = true;
        state.transitionProgress = 0.0f;
        transitionStartMs = millis();
        transitionDurationMs = transitionMs;
    }

    Serial.printf("[Face] Expression → %u (transition %ums)\n",
        (uint8_t)expr, transitionMs);
}

face::Expression face::getExpression() {
    return state.expression;
}

void face::feedAudioAmplitude(float amplitude) {
    currentAmplitude = amplitude < 0.0f ? 0.0f : (amplitude > 1.0f ? 1.0f : amplitude);
}

const face::FaceState& face::getState() {
    return state;
}
