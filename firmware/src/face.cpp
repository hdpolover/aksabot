#include "face.h"
#include <Arduino.h>
#include <cstdlib>
#include <cmath>
#include <esp_random.h>

// ── Internal state ─────────────────────────────────────
static face::FaceState state;
static face::Expression targetExpr = face::Expression::IDLE;

// Blink timing
static uint32_t nextBlinkMs = 0;
static uint32_t blinkStartMs = 0;
static const uint16_t BLINK_DURATION_MS = 120;

// Transition
static uint32_t transitionStartMs = 0;
static uint16_t transitionDurationMs = 200;

// Thinking
static uint32_t lastDotTickMs = 0;

// Pupil drift targets
static float driftTX = 0, driftTY = 0;
static uint32_t nextDriftSwitch = 0;

// Idle fidget
static uint32_t nextFidgetMs = 0;

// Sad teardrop
static uint32_t lastTearSpawnMs = 0;

// Speaking
static float currentAmplitude = 0.0f;

// ── Helpers ────────────────────────────────────────────

static float flerp(float a, float b, float t) { return a + (b - a) * t; }

static bool canBlink(face::Expression e) {
    return e == face::Expression::IDLE ||
           e == face::Expression::SPEAKING ||
           e == face::Expression::ENCOURAGING ||
           e == face::Expression::CALM ||
           e == face::Expression::FOCUSED ||
           e == face::Expression::HAPPY ||
           e == face::Expression::OFFLINE;
}

// ── Public API ─────────────────────────────────────────

void face::init() {
    memset(&state, 0, sizeof(state));
    state.expression = Expression::IDLE;
    state.eyesOpen = true;
    state.blinkScale = 1.0f;
    targetExpr = Expression::IDLE;

    uint32_t now = millis();
    nextBlinkMs = now + 2000;
    nextDriftSwitch = now + 1000;
    nextFidgetMs = now + 5000;
    lastTearSpawnMs = now;

    Serial.println("[Face] Initialized");
}

void face::tick(uint32_t nowMs) {
    const float dt = 0.016f;  // ~60fps

    // ── Transition ─────────────────────────────────
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

    face::Expression active = state.transitionActive ? targetExpr : state.expression;

    // ── Blink ──────────────────────────────────────
    if (state.blinking) {
        float bt = (float)(nowMs - blinkStartMs) / (float)BLINK_DURATION_MS;
        if (bt >= 1.0f) {
            state.blinking = false;
            state.blinkScale = 1.0f;
            state.eyesOpen = true;
            nextBlinkMs = nowMs + 3000 + (esp_random() % 5000);
        } else {
            // Close → hold → open
            if (bt < 0.4f)       state.blinkScale = 1.0f - bt / 0.4f;
            else if (bt < 0.6f)  state.blinkScale = 0.0f;
            else                 state.blinkScale = (bt - 0.6f) / 0.4f;
            state.eyesOpen = (state.blinkScale > 0.05f);
        }
    } else if (canBlink(active) && nowMs >= nextBlinkMs) {
        state.blinking = true;
        blinkStartMs = nowMs;
    } else if (active == Expression::SLEEPING) {
        state.eyesOpen = false;
        state.blinkScale = 0.0f;
    } else {
        state.eyesOpen = true;
        state.blinkScale = 1.0f;
    }

    // ── Pupil drift ────────────────────────────────
    if (active == Expression::IDLE || active == Expression::CALM || active == Expression::SPEAKING) {
        state.driftX = flerp(state.driftX, driftTX, 0.03f);
        state.driftY = flerp(state.driftY, driftTY, 0.03f);
        if (nowMs >= nextDriftSwitch) {
            driftTX = ((float)(esp_random() % 100) / 100.0f - 0.5f) * 16.0f;
            driftTY = ((float)(esp_random() % 100) / 100.0f - 0.5f) * 14.0f;
            nextDriftSwitch = nowMs + 2500 + (esp_random() % 3000);
        }
    } else {
        state.driftX = flerp(state.driftX, 0, 0.1f);
        state.driftY = flerp(state.driftY, 0, 0.1f);
    }

    // ── Thinking dots ──────────────────────────────
    if (active == Expression::THINKING && (nowMs - lastDotTickMs) >= 400) {
        state.thinkDots = (state.thinkDots + 1) % 4;
        lastDotTickMs = nowMs;
    }
    state.thinkingDotCount = state.thinkDots;  // legacy alias

    // ── Breathing (sleeping) ───────────────────────
    if (active == Expression::SLEEPING) {
        state.breathPhase += dt / 4.0f;
        if (state.breathPhase > 1.0f) state.breathPhase -= 1.0f;
    }

    // ── Mouth amplitude smoothing ──────────────────
    state.mouthAmp = flerp(state.mouthAmp, (active == Expression::SPEAKING) ? currentAmplitude : 0, 0.25f);
    state.mouthOpenness = state.mouthAmp;  // legacy alias

    // ── Listening pulse ────────────────────────────
    if (active == Expression::LISTENING) state.listenPhase += dt * 4.0f;

    // ── Idle fidget ────────────────────────────────
    if (active == Expression::IDLE) {
        state.fidgetX = flerp(state.fidgetX, 0, 0.05f);
        state.fidgetY = flerp(state.fidgetY, 0, 0.05f);
        if (nowMs >= nextFidgetMs) {
            state.fidgetX = ((float)(esp_random() % 100) / 100.0f - 0.5f) * 3.0f;
            state.fidgetY = ((float)(esp_random() % 100) / 100.0f - 0.5f) * 2.0f;
            nextFidgetMs = nowMs + 10000 + (esp_random() % 10000);
        }
    } else {
        state.fidgetX = flerp(state.fidgetX, 0, 0.1f);
        state.fidgetY = flerp(state.fidgetY, 0, 0.1f);
    }

    // ── Happy bounce ───────────────────────────────
    if (active == Expression::HAPPY)
        state.bounceY = sinf(nowMs / 300.0f) * 4.0f;
    else
        state.bounceY = flerp(state.bounceY, 0, 0.1f);

    // ── Sad teardrop ───────────────────────────────
    if (active == Expression::SAD) {
        if (state.tearActive) {
            state.tearY += 1.5f;
            if (state.tearY > 60) state.tearActive = false;
        } else if (nowMs - lastTearSpawnMs > 3000 + (esp_random() % 2000)) {
            state.tearActive = true;
            state.tearY = 10;
            state.tearSide = (esp_random() % 2) ? -1 : 1;
            lastTearSpawnMs = nowMs;
        }
    } else {
        state.tearActive = false;
    }

    // ── Glow pulse ─────────────────────────────────
    state.glowPhase += dt * 1.5f;
    if (state.glowPhase > 6.2832f) state.glowPhase -= 6.2832f;
}

void face::setExpression(Expression expr, uint16_t transitionMs) {
    if (expr == targetExpr && !state.transitionActive) return;
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

    // Reset expression-specific state
    state.thinkDots = 0;
    lastDotTickMs = millis();
    state.tearActive = false;
    state.bounceY = 0;
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
