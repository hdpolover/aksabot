#include "battery.h"
#include "config.h"
#include <Arduino.h>
#include "soc/usb_serial_jtag_reg.h"

namespace battery {

// ── Constants ─────────────────────────────────────────────────────────────────

// Voltage divider ratio on GPIO9. Board uses two equal resistors (~100K each),
// so the pin sees half the battery voltage. Multiply ADC result by 2 to get
// the real battery voltage. Adjust this value if readings drift vs a multimeter.
static constexpr float BATTERY_SCALE    = 2.0f;

// USB/charging detection: LiPo maxes at ~4.20V. Anything above indicates
// external power (USB). Lowered from 4300 to 4200 — charging IC on the
// ES3C28P board may not push much past saturation voltage.
static constexpr float  USB_VOLTAGE_MIN = 4200.0f;  // mV

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

// Charging trend detection: if voltage rises by ≥ this amount between two
// consecutive 30-second reads, the battery is likely charging (even if the
// absolute voltage hasn't crossed USB_VOLTAGE_MIN yet).
static constexpr int16_t CHARGING_RISE_THRESHOLD = 15;  // mV between reads

// ── Module state ──────────────────────────────────────────────────────────────

static uint8_t  lastPercent = 255;  // 255 = unknown until first read
static uint16_t lastMv      = 0;
static uint16_t prevMv      = 0;    // previous reading for trend detection
static bool     usbPowered  = false;
static bool     charging    = false; // true if voltage is rising (trend-based)

// ── Discharge rate tracking ──────────────────────────────────────────────────
static constexpr int RATE_WINDOW = 10;           // samples (5 min at 30s intervals)
static uint16_t rateBuffer[RATE_WINDOW] = {};    // circular buffer of mV readings
static int rateIndex = 0;
static int rateSamples = 0;                       // how many samples we've collected

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
    analogSetPinAttenuation(BATTERY_ADC, ADC_11db);  // Arduino ESP32 name for 11/12 dB attenuation
    Serial.println("[Battery] Init");
}

// Detect USB host connection via USB Serial/JTAG SOF (Start-of-Frame) bits.
// A USB host sends SOF packets every 1ms. If we clear the SOF status bit and
// it reappears within a few ms, a host is physically connected. This works
// even when the battery is fully charged and voltage alone can't distinguish
// USB-powered from battery-full.
static bool detectUsbConnected() {
    // Clear the SOF interrupt raw status bit
    REG_SET_BIT(USB_SERIAL_JTAG_INT_CLR_REG, USB_SERIAL_JTAG_SOF_INT_CLR);
    delayMicroseconds(1500);  // SOF fires every 1ms — wait 1.5ms
    // If the bit came back, a USB host is sending frames
    return (REG_READ(USB_SERIAL_JTAG_INT_RAW_REG) & USB_SERIAL_JTAG_SOF_INT_RAW) != 0;
}

uint8_t readPercent() {
    // Average 16 samples using the ESP32-S3's calibrated millivolt API.
    // analogReadMilliVolts() uses factory-burned eFuse calibration data
    // and handles the non-linear ADC transfer curve internally — much more
    // accurate than manual (raw/4095)*3.3V math.
    uint32_t sumMv = 0;
    uint32_t sumRaw = 0;
    for (int i = 0; i < 16; i++) {
        sumRaw += analogRead(BATTERY_ADC);
        sumMv  += analogReadMilliVolts(BATTERY_ADC);
        delayMicroseconds(100);
    }
    uint16_t rawAvg  = static_cast<uint16_t>(sumRaw / 16);
    uint16_t pinMv   = static_cast<uint16_t>(sumMv / 16);   // calibrated pin voltage
    uint16_t mv      = static_cast<uint16_t>(pinMv * BATTERY_SCALE + 0.5f);  // after divider

    // Trend detection: is voltage rising since last read?
    int16_t delta = static_cast<int16_t>(mv) - static_cast<int16_t>(prevMv);
    bool voltageRising = (prevMv > 0) && (delta >= CHARGING_RISE_THRESHOLD);
    prevMv = mv;

    // Primary USB detection: SOF frame check (hardware-level, works regardless
    // of battery voltage). Fallback: high voltage threshold for edge cases.
    bool usbDetected = detectUsbConnected();
    usbPowered = usbDetected || (mv >= static_cast<uint16_t>(USB_VOLTAGE_MIN));
    charging   = usbPowered || voltageRising;

    // Update shared state
    lastMv = mv;

    // Diagnostic log
    Serial.printf("[Battery] raw=%u pinMv=%u batMv=%u delta=%+dmV usb=%s(sof=%s) charging=%s\n",
                  rawAvg, pinMv, mv, delta,
                  usbPowered ? "Y" : "N",
                  usbDetected ? "Y" : "N",
                  charging   ? "Y" : "N");

    if (charging) {
        // Reset rate tracking when charging
        rateSamples = 0;
        rateIndex = 0;
        lastPercent = 255;
        return 255;
    }

    lastPercent = voltageToPercent(mv);
    Serial.printf("[Battery] %u mV → %u%%\n", mv, lastPercent);

    // Record voltage for discharge rate tracking (only when not charging)
    if (!charging) {
        rateBuffer[rateIndex] = mv;
        rateIndex = (rateIndex + 1) % RATE_WINDOW;
        if (rateSamples < RATE_WINDOW) rateSamples++;
    } else {
        // Reset rate tracking when charging
        rateSamples = 0;
        rateIndex = 0;
    }

    return lastPercent;
}

bool isUsbPowered() {
    return usbPowered;
}

bool isCharging() {
    return charging;
}

bool isLow() {
    return !charging && lastPercent != 255 && lastPercent <= LOW_THRESHOLD;
}

bool isCritical() {
    return !charging && lastPercent != 255 && lastPercent <= CRITICAL_THRESHOLD;
}

int16_t minutesRemaining() {
    if (charging || rateSamples < 3) return -1;  // need at least 3 samples

    // Oldest sample in the ring buffer
    int oldestIdx = (rateSamples < RATE_WINDOW)
        ? 0
        : rateIndex;  // rateIndex points to the next write = oldest
    uint16_t oldestMv = rateBuffer[oldestIdx];

    // Newest sample
    int newestIdx = (rateIndex - 1 + RATE_WINDOW) % RATE_WINDOW;
    uint16_t newestMv = rateBuffer[newestIdx];

    // Time span of the window in minutes (samples * 30s interval)
    float spanMinutes = rateSamples * 0.5f;  // 30s = 0.5 min

    // Drain rate in mV per minute
    float drainMvPerMin = (float)(oldestMv - newestMv) / spanMinutes;

    // Not draining (stable or rising without being flagged as charging)
    if (drainMvPerMin <= 0.5f) return -1;

    // mV remaining until empty (3400mV = 0%)
    float mvRemaining = (float)newestMv - 3400.0f;
    if (mvRemaining <= 0) return 0;

    int16_t minutes = (int16_t)(mvRemaining / drainMvPerMin);
    // Cap at 24 hours to avoid absurd estimates
    if (minutes > 1440) minutes = 1440;

    return minutes;
}

uint16_t lastVoltageMillivolts() {
    return lastMv;
}

}  // namespace battery
