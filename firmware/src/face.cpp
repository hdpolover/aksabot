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

// ── Idle micro-animations ─────────────────────────────
// Each "act" is a short self-contained animation that plays while idle.
enum class IdleAct : uint8_t {
    NONE,           // Normal idle
    LOOK_AROUND,    // Eyes sweep left, pause, sweep right
    DOUBLE_BLINK,   // Two quick blinks
    CURIOUS,        // Eyes widen + drift to one side
    YAWN,           // Mouth opens, eyes squeeze, settle
    DISAPPEAR,      // Eyes shrink to dots, pause, pop back
    EYE_ROLL,       // Pupils trace a circle
    WINK,           // One eye closes briefly
    BOUNCE,         // Quick little hop
};
static const uint8_t IDLE_ACT_COUNT = 8;  // Number of acts (excluding NONE)

static IdleAct currentAct = IdleAct::NONE;
static uint32_t actStartMs = 0;
static uint32_t nextActMs = 0;
static int8_t actParam = 0;         // e.g., which side to wink

// Configurable idle interval (default 8-20s)
static uint32_t idleMinMs = 8000;
static uint32_t idleRangeMs = 12000;

// Sad teardrop
static uint32_t lastTearSpawnMs = 0;

// Speaking
static float currentAmplitude = 0.0f;
static float prevAmplitude = 0.0f;       // For peak detection
static uint32_t peakDecayMs = 0;         // When peak flag should clear

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

    state.leftEyeScale = 1.0f;
    state.rightEyeScale = 1.0f;
    state.popScale = 1.0f;

    uint32_t now = millis();
    nextBlinkMs = now + 2000;
    nextDriftSwitch = now + 1000;
    nextFidgetMs = now + 5000;
    nextActMs = now + idleMinMs + (esp_random() % idleRangeMs);  // First act
    lastTearSpawnMs = now;
    currentAct = IdleAct::NONE;

    Serial.println("[Face] Initialized");
}

void face::tick(uint32_t nowMs) {
    const float dt = 0.016f;  // ~60fps
    bool isSpeechActive = currentAmplitude > 0.01f;

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
    } else if (canBlink(active) && nowMs >= nextBlinkMs && state.audioEnergy < 0.3f) {
        // Suppress blinks during loud speech — eyes stay open for expressiveness
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
    if (active == Expression::CONFUSED) {
        // Confused: faster, wider side-to-side look ("huh? what?")
        state.driftX = flerp(state.driftX, driftTX, 0.08f);
        state.driftY = flerp(state.driftY, driftTY, 0.04f);
        if (nowMs >= nextDriftSwitch) {
            driftTX = ((float)(esp_random() % 100) / 100.0f - 0.5f) * 24.0f;
            driftTY = ((float)(esp_random() % 100) / 100.0f - 0.5f) * 8.0f;
            nextDriftSwitch = nowMs + 800 + (esp_random() % 1200);
        }
    } else if (active == Expression::IDLE || active == Expression::CALM ||
               active == Expression::SPEAKING || isSpeechActive) {
        // Natural gaze drift: used during idle AND while speaking in any expression
        state.driftX = flerp(state.driftX, driftTX, 0.03f);
        state.driftY = flerp(state.driftY, driftTY, 0.03f);
        if (nowMs >= nextDriftSwitch) {
            float range = isSpeechActive ? 10.0f : 16.0f;  // Smaller drift while talking
            driftTX = ((float)(esp_random() % 100) / 100.0f - 0.5f) * range;
            driftTY = ((float)(esp_random() % 100) / 100.0f - 0.5f) * (range * 0.7f);
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

    // ── Breathing cycle (always runs — used by sleeping, idle mouth, sad tremble)
    state.breathPhase += dt / 4.0f;
    if (state.breathPhase > 1.0f) state.breathPhase -= 1.0f;

    // ── Mouth amplitude smoothing ──────────────────
    // Feed amplitude for ANY expression (not just SPEAKING) — enables emotion-aware speech
    float targetAmp = isSpeechActive ? currentAmplitude : 0.0f;
    state.mouthAmp = flerp(state.mouthAmp, targetAmp, 0.25f);
    state.mouthOpenness = state.mouthAmp;  // legacy alias

    // ── Audio energy tracking (for eye/brow reactivity) ──
    state.audioEnergy = flerp(state.audioEnergy, currentAmplitude, 0.15f);

    // Peak detection: sudden amplitude spike
    float ampDelta = currentAmplitude - prevAmplitude;
    if (ampDelta > 0.25f && !state.energyPeak) {
        state.energyPeak = true;
        peakDecayMs = nowMs + 400;  // brow raise lasts 400ms
    }
    if (state.energyPeak && nowMs >= peakDecayMs) {
        state.energyPeak = false;
    }
    prevAmplitude = currentAmplitude;

    // Speaking nod: subtle vertical bounce from amplitude
    if (isSpeechActive) {
        state.speakingNodY = flerp(state.speakingNodY, -currentAmplitude * 2.0f, 0.2f);
    } else {
        state.speakingNodY = flerp(state.speakingNodY, 0.0f, 0.1f);
    }

    // ── Listening pulse ────────────────────────────
    if (active == Expression::LISTENING) state.listenPhase += dt * 4.0f;

    // ── Idle micro-animations ──────────────────────
    // Reset per-frame overrides
    state.leftEyeScale = 1.0f;
    state.rightEyeScale = 1.0f;
    state.yawnAmp = 0.0f;
    state.popScale = 1.0f;

    // Audio-reactive eye scale during speech (any expression)
    if (isSpeechActive && active != Expression::SLEEPING && active != Expression::THINKING) {
        float eyeScale;
        if (state.audioEnergy < 0.15f) eyeScale = 0.92f;
        else if (state.audioEnergy > 0.4f) eyeScale = 1.10f;
        else eyeScale = 1.0f;
        state.leftEyeScale = eyeScale;
        state.rightEyeScale = eyeScale;
    }

    if (active == Expression::IDLE) {
        // Base fidget (subtle position jitter)
        state.fidgetX = flerp(state.fidgetX, 0, 0.05f);
        state.fidgetY = flerp(state.fidgetY, 0, 0.05f);

        // Schedule next micro-animation
        if (currentAct == IdleAct::NONE && nowMs >= nextActMs) {
            uint8_t pick = esp_random() % IDLE_ACT_COUNT;
            currentAct = (IdleAct)(pick + 1);
            actStartMs = nowMs;
            actParam = (esp_random() % 2) ? -1 : 1;  // random side
        }

        // Run current act
        if (currentAct != IdleAct::NONE) {
            float t = (float)(nowMs - actStartMs);  // ms since act started

            switch (currentAct) {
                case IdleAct::LOOK_AROUND: {
                    // 2.5s: look left → pause → look right → center
                    float phase = t / 2500.0f;
                    if (phase < 0.25f) {
                        driftTX = -20.0f;
                        driftTY = 0;
                    } else if (phase < 0.5f) {
                        driftTX = -20.0f;
                    } else if (phase < 0.75f) {
                        driftTX = 20.0f;
                    } else if (phase < 1.0f) {
                        driftTX = 0;
                        driftTY = 0;
                    } else {
                        currentAct = IdleAct::NONE;
                    }
                    break;
                }

                case IdleAct::DOUBLE_BLINK: {
                    // 600ms: blink, brief open, blink again
                    if (t < 120)       state.blinkScale = 1.0f - t / 120.0f;
                    else if (t < 200)  state.blinkScale = 0.0f;
                    else if (t < 300)  state.blinkScale = (t - 200) / 100.0f;
                    else if (t < 350)  state.blinkScale = 1.0f;
                    else if (t < 470)  state.blinkScale = 1.0f - (t - 350) / 120.0f;
                    else if (t < 550)  state.blinkScale = 0.0f;
                    else if (t < 650)  state.blinkScale = (t - 550) / 100.0f;
                    else { state.blinkScale = 1.0f; currentAct = IdleAct::NONE; }
                    state.eyesOpen = (state.blinkScale > 0.05f);
                    break;
                }

                case IdleAct::CURIOUS: {
                    // 2s: eyes widen + drift to one side, then settle
                    float phase = t / 2000.0f;
                    if (phase < 0.3f) {
                        float ease = phase / 0.3f;
                        state.leftEyeScale = 1.0f + ease * 0.2f;
                        state.rightEyeScale = 1.0f + ease * 0.2f;
                        driftTX = actParam * 18.0f * ease;
                        driftTY = -4.0f * ease;
                    } else if (phase < 0.7f) {
                        state.leftEyeScale = 1.2f;
                        state.rightEyeScale = 1.2f;
                        driftTX = actParam * 18.0f;
                        driftTY = -4.0f;
                    } else if (phase < 1.0f) {
                        float ease = (phase - 0.7f) / 0.3f;
                        state.leftEyeScale = 1.2f - ease * 0.2f;
                        state.rightEyeScale = 1.2f - ease * 0.2f;
                        driftTX = actParam * 18.0f * (1.0f - ease);
                        driftTY = -4.0f * (1.0f - ease);
                    } else {
                        currentAct = IdleAct::NONE;
                    }
                    break;
                }

                case IdleAct::YAWN: {
                    // 2.5s: eyes squeeze, mouth opens wide, then close
                    float phase = t / 2500.0f;
                    if (phase < 0.2f) {
                        float ease = phase / 0.2f;
                        state.leftEyeScale = 1.0f - ease * 0.6f;
                        state.rightEyeScale = 1.0f - ease * 0.6f;
                        state.yawnAmp = ease * 0.8f;
                    } else if (phase < 0.6f) {
                        state.leftEyeScale = 0.4f;
                        state.rightEyeScale = 0.4f;
                        state.yawnAmp = 0.8f;
                    } else if (phase < 1.0f) {
                        float ease = (phase - 0.6f) / 0.4f;
                        state.leftEyeScale = 0.4f + ease * 0.6f;
                        state.rightEyeScale = 0.4f + ease * 0.6f;
                        state.yawnAmp = 0.8f * (1.0f - ease);
                    } else {
                        currentAct = IdleAct::NONE;
                    }
                    break;
                }

                case IdleAct::DISAPPEAR: {
                    // 2s: shrink to nothing, pause, pop back with overshoot
                    float phase = t / 2000.0f;
                    if (phase < 0.25f) {
                        state.popScale = 1.0f - (phase / 0.25f);
                    } else if (phase < 0.55f) {
                        state.popScale = 0.0f;
                    } else if (phase < 0.75f) {
                        float ease = (phase - 0.55f) / 0.2f;
                        state.popScale = ease * 1.15f;  // overshoot
                    } else if (phase < 1.0f) {
                        float ease = (phase - 0.75f) / 0.25f;
                        state.popScale = 1.15f - ease * 0.15f;  // settle to 1.0
                    } else {
                        state.popScale = 1.0f;
                        currentAct = IdleAct::NONE;
                    }
                    break;
                }

                case IdleAct::EYE_ROLL: {
                    // 1.5s: pupils trace a circle
                    float phase = t / 1500.0f;
                    if (phase < 1.0f) {
                        float angle = phase * 2.0f * 3.14159f;
                        driftTX = cosf(angle) * 14.0f;
                        driftTY = sinf(angle) * 10.0f;
                    } else {
                        driftTX = 0; driftTY = 0;
                        currentAct = IdleAct::NONE;
                    }
                    break;
                }

                case IdleAct::WINK: {
                    // 800ms: one eye closes and opens
                    float phase = t / 800.0f;
                    float scale;
                    if (phase < 0.25f)       scale = 1.0f - phase / 0.25f;
                    else if (phase < 0.6f)   scale = 0.0f;
                    else if (phase < 1.0f)   scale = (phase - 0.6f) / 0.4f;
                    else { scale = 1.0f; currentAct = IdleAct::NONE; }

                    if (actParam > 0) state.rightEyeScale = scale;
                    else              state.leftEyeScale = scale;
                    break;
                }

                case IdleAct::BOUNCE: {
                    // 800ms: quick hop up and settle
                    float phase = t / 800.0f;
                    if (phase < 0.3f) {
                        state.bounceY = -sinf(phase / 0.3f * 3.14159f) * 8.0f;
                    } else if (phase < 0.6f) {
                        state.bounceY = -sinf((phase - 0.3f) / 0.3f * 3.14159f) * 3.0f;
                    } else if (phase < 1.0f) {
                        state.bounceY = flerp(state.bounceY, 0, 0.15f);
                    } else {
                        state.bounceY = 0;
                        currentAct = IdleAct::NONE;
                    }
                    break;
                }

                default:
                    currentAct = IdleAct::NONE;
                    break;
            }

            // When act finishes, schedule next one
            if (currentAct == IdleAct::NONE) {
                nextActMs = nowMs + idleMinMs + (esp_random() % idleRangeMs);
            }
        }
    } else {
        // Not idle — reset
        state.fidgetX = flerp(state.fidgetX, 0, 0.1f);
        state.fidgetY = flerp(state.fidgetY, 0, 0.1f);
        if (currentAct != IdleAct::NONE) {
            currentAct = IdleAct::NONE;
            nextActMs = 0;
        }
    }

    // ── Bounce / nod ──────────────────────────────
    if (active == Expression::HAPPY) {
        state.bounceY = sinf(nowMs / 300.0f) * 4.0f;
    } else if (active == Expression::LISTENING) {
        // Gentle nod — slower, smaller, like nodding along
        state.bounceY = sinf(nowMs / 600.0f) * 3.0f;
    } else if (currentAct != IdleAct::BOUNCE) {
        // Don't zero out during idle BOUNCE act
        state.bounceY = flerp(state.bounceY, 0, 0.1f);
    }

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

void face::setIdleInterval(uint32_t minMs, uint32_t rangeMs) {
    idleMinMs = minMs;
    idleRangeMs = rangeMs;
    Serial.printf("[Face] Idle interval: %lu-%lums\n", minMs, minMs + rangeMs);
}
