#include "battery.h"
#include "config.h"
#include <Arduino.h>
#include <driver/adc.h>

namespace battery {

// ── Constants ─────────────────────────────────────────────────────────────────

// Voltage divider ratio on GPIO9. Board uses two equal resistors (~100K each),
// so the pin sees half the battery voltage. Multiply ADC result by 2 to get
// the real battery voltage. Adjust this value if readings drift vs a multimeter.
static constexpr float BATTERY_SCALE    = 2.0f;

static constexpr float  ADC_REF_VOLTS   = 3.3f;
static constexpr int    ADC_MAX         = 4095;
static constexpr float  USB_VOLTAGE_MIN = 4100.0f;  // mV — above this, assume USB power

// ── Piecewise LiPo discharge curve ────────────────────────────────────────────
struct CurvePoint { uint16_t mv; uint8_t pct; };

static constexpr CurvePoint kCurve[] = {
    { 4050, 100 },
    { 3900,  75 },
    { 3750,  50 },
    { 3600,  25 },
    { 3500,  10 },
    { 3400,   0 },
};
static constexpr int kCurveLen = sizeof(kCurve) / sizeof(kCurve[0]);

// ── Module state ──────────────────────────────────────────────────────────────

static uint8_t  lastPercent = 0;
static uint16_t lastMv      = 0;
static bool     usbPowered  = false;

// ── Private helpers ───────────────────────────────────────────────────────────

static uint8_t voltageToPercent(uint16_t mv) {
    // Above highest breakpoint → full
    if (mv >= kCurve[0].mv) return 100;
    // Below lowest breakpoint → empty
    if (mv <= kCurve[kCurveLen - 1].mv) return 0;

    // Find the segment this voltage falls in
    for (int i = 0; i < kCurveLen - 1; i++) {
        const CurvePoint& hi = kCurve[i];
        const CurvePoint& lo = kCurve[i + 1];
        if (mv <= hi.mv && mv >= lo.mv) {
            // Linear interpolation within the segment
            float ratio = static_cast<float>(mv - lo.mv) /
                          static_cast<float>(hi.mv - lo.mv);
            return static_cast<uint8_t>(lo.pct + ratio * (hi.pct - lo.pct) + 0.5f);
        }
    }
    return 0;
}

// ── Public API ────────────────────────────────────────────────────────────────

void init() {
    analogSetPinAttenuation(BATTERY_ADC, ADC_11db);
    Serial.println("[Battery] Init");
}

uint8_t readPercent() {
    // Average 16 samples with 100µs gap to reduce ADC noise
    uint32_t sum = 0;
    for (int i = 0; i < 16; i++) {
        sum += analogRead(BATTERY_ADC);
        delayMicroseconds(100);
    }
    uint16_t raw = static_cast<uint16_t>(sum / 16);

    // Convert ADC value → millivolts (after divider scale-up)
    float adcVoltage = (raw / static_cast<float>(ADC_MAX)) * ADC_REF_VOLTS;
    uint16_t mv = static_cast<uint16_t>(adcVoltage * BATTERY_SCALE * 1000.0f + 0.5f);

    // Update shared state
    lastMv     = mv;
    usbPowered = (mv >= static_cast<uint16_t>(USB_VOLTAGE_MIN));

    if (usbPowered) {
        lastPercent = 255;
        Serial.printf("[Battery] USB powered (%u mV)\n", mv);
        return 255;
    }

    lastPercent = voltageToPercent(mv);
    Serial.printf("[Battery] %u mV → %u%%\n", mv, lastPercent);
    return lastPercent;
}

bool isUsbPowered() {
    return usbPowered;
}

bool isLow() {
    return !usbPowered && lastPercent != 255 && lastPercent <= LOW_THRESHOLD;
}

bool isCritical() {
    return !usbPowered && lastPercent != 255 && lastPercent <= CRITICAL_THRESHOLD;
}

uint16_t lastVoltageMillivolts() {
    return lastMv;
}

}  // namespace battery
