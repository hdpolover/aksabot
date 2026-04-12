#pragma once
#include <cstdint>
#include <functional>

/// APDS-9960 gesture and proximity sensor module.
///
/// Provides:
///   - Proximity detection (someone approaching the desk)
///   - Gesture recognition (wave, swipe up/down/left/right)
///   - Ambient light sensing (for auto-brightness)
///
/// Uses I2C (shared bus with touch + audio codec, addr 0x39).
/// INT pin on GPIO_SPARE_3 (14) for interrupt-driven detection.
///
/// Usage:
///   gesture::init();
///   gesture::onGesture([](gesture::Type g) { ... });
///   gesture::onProximity([](bool near) { ... });
///   // In loop or task:
///   gesture::tick(millis());
namespace gesture {

/// Gesture types detected by APDS-9960.
enum class Type : uint8_t {
    NONE,
    WAVE,           // Hand wave (any rapid proximity change)
    SWIPE_UP,
    SWIPE_DOWN,
    SWIPE_LEFT,
    SWIPE_RIGHT,
};

/// Callback for gesture events.
using GestureCallback = std::function<void(Type gesture)>;

/// Callback for proximity state changes (near = within ~15cm).
using ProximityCallback = std::function<void(bool near)>;

/// Callback for ambient light level changes.
using LightCallback = std::function<void(uint16_t lux)>;

/// Initialize APDS-9960 sensor on I2C bus.
/// Returns false if sensor not found.
bool init();

/// Register callback for gesture events.
void onGesture(GestureCallback cb);

/// Register callback for proximity changes.
void onProximity(ProximityCallback cb);

/// Register callback for ambient light changes.
void onLight(LightCallback cb);

/// Poll sensor and fire callbacks. Call from main loop.
void tick(uint32_t nowMs);

/// Get raw proximity value (0=far, 255=very close).
uint8_t getProximity();

/// Get ambient light level (lux approximation).
uint16_t getAmbientLight();

/// Check if someone is near the sensor.
bool isNear();

/// Enable or disable gesture detection (saves power when not needed).
void setGestureEnabled(bool enabled);

/// Enable or disable proximity detection.
void setProximityEnabled(bool enabled);

}  // namespace gesture
