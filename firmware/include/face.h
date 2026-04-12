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
    HAPPY,          // Wide grin, bouncing
    SAD,            // Frown, teardrops
    SHRUG,          // Head shake + bubble blow — "idk/whatever"
    SURPRISED,      // Wide eyes, raised brows, O-mouth — "oh wow!"
    SHOCKED,        // Max-wide eyes, tiny pupils, agape — frozen disbelief
    ANGRY,          // Squinted eyes, V-brows, tight frown — irritated
    DISTURBED,      // Asymmetric eyes, wobbly mouth — creeped out
    COUNT
};

/// Animation frame data readable by the display driver.
struct FaceState {
    Expression expression;

    // Blink
    bool  eyesOpen;
    bool  blinking;
    float blinkScale;           // 1.0 = open, 0.0 = closed

    // Mouth
    float mouthAmp;             // 0.0-1.0, smoothed audio amplitude

    // Sleeping
    float breathPhase;          // 0.0-1.0 cycle

    // Thinking
    uint8_t thinkDots;          // 0-3 cycling dots

    // Pupil drift
    float driftX, driftY;

    // Idle fidget
    float fidgetX, fidgetY;

    // Listening pulse
    float listenPhase;

    // Happy bounce
    float bounceY;

    // Sad teardrop
    bool  tearActive;
    float tearY;
    int8_t tearSide;            // -1 = left eye, +1 = right eye

    // Glow pulse
    float glowPhase;

    // Idle micro-animation
    float leftEyeScale;         // Independent scale for left eye (1.0 = normal)
    float rightEyeScale;        // Independent scale for right eye (1.0 = normal)
    float yawnAmp;              // Mouth openness during yawn (0.0-1.0)
    float popScale;             // Overall face scale for pop effects (1.0 = normal)

    // Audio-reactive speaking
    float audioEnergy;          // Smoothed rolling energy (0.0-1.0)
    bool  energyPeak;           // True when sudden amplitude spike detected
    float speakingNodY;         // Subtle head nod driven by amplitude

    // Shrug animation
    float shrugPhase;           // 0.0-1.0 progress of head-shake + bubble animation

    // Transition
    bool  transitionActive;
    float transitionProgress;

    // Legacy compat
    uint8_t thinkingDotCount;   // alias for thinkDots
    float mouthOpenness;        // alias for mouthAmp
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

/// Set idle micro-animation interval.
/// minMs = minimum wait between animations, rangeMs = random range added on top.
/// Default: minMs=8000, rangeMs=12000 (8-20s between animations).
void setIdleInterval(uint32_t minMs, uint32_t rangeMs);

}  // namespace face
