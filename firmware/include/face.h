#pragma once
#include <cstdint>

/// Face animation state machine.
///
/// Manages which expression to show, blinking, and transition timing.
/// Hardware-independent — call tick() regularly and read the current
/// state for the display driver to render.
namespace face {

/// Face expressions. Each maps to a sprite set or procedural animation.
enum class Expression : uint8_t {
    IDLE,           // Default happy face, occasional blinks
    LISTENING,      // Wide eyes, pulsing indicator
    THINKING,       // Eyes looking around, loading dots
    SPEAKING,       // Mouth animation synced to audio amplitude
    CONFUSED,       // Tilted eyes, question mark
    SLEEPING,       // Closed eyes, gentle breathing cycle
    OFFLINE,        // Greyed-out face, Wi-Fi X icon
    ENCOURAGING,    // Cheerful eyes, upward expression (reminders)
    CALM,           // Soft eyes, relaxed (eye break, focus)
    FOCUSED,        // Determined eyes, slight squint (pomodoro focus)
};

/// Animation frame data readable by the display driver.
struct FaceState {
    Expression expression;
    bool eyesOpen;              // false during blink or sleeping
    float mouthOpenness;        // 0.0-1.0, driven by audio amplitude
    float breathPhase;          // 0.0-1.0 cycle for sleeping animation
    uint8_t thinkingDotCount;   // 0-3 for loading dots animation
    bool transitionActive;      // true during expression change blend
    float transitionProgress;   // 0.0-1.0 during transition
};

/// Initialize the face system.
void init();

/// Advance animations by one tick. Call from display task (e.g., 30fps = every 33ms).
void tick(uint32_t nowMs);

/// Set the target expression. Transition happens over transitionMs.
void setExpression(Expression expr, uint16_t transitionMs = 200);

/// Get the current expression (may differ from target during transition).
Expression getExpression();

/// Feed audio amplitude for mouth animation during SPEAKING.
/// Value 0.0 (silence) to 1.0 (max volume).
void feedAudioAmplitude(float amplitude);

/// Get the current face state for rendering.
const FaceState& getState();

}  // namespace face
