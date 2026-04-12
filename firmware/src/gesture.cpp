#include "gesture.h"
#include "config.h"
#include <Wire.h>
#include <Arduino.h>

// ── APDS-9960 I2C registers ──────────────────────────────────
#define APDS_ADDR         0x39

// Control registers
#define REG_ENABLE        0x80
#define REG_ATIME         0x81  // ALS integration time
#define REG_PILT          0x89  // Proximity interrupt low threshold
#define REG_PIHT          0x8B  // Proximity interrupt high threshold
#define REG_PERS          0x8C  // Interrupt persistence
#define REG_CONFIG2       0x90
#define REG_PPULSE        0x8E  // Proximity pulse count + length
#define REG_CONTROL       0x8F  // Gain control
#define REG_ID            0x92  // Device ID (should be 0xAB)
#define REG_STATUS        0x93
#define REG_CDATAL        0x94  // Clear/ambient light low byte
#define REG_CDATAH        0x95
#define REG_PDATA         0x9C  // Proximity data

// Gesture registers
#define REG_GPENTH        0xA0  // Gesture proximity enter threshold
#define REG_GEXTH         0xA1  // Gesture exit threshold
#define REG_GCONF1        0xA2
#define REG_GCONF2        0xA3
#define REG_GOFFSET_U     0xA4
#define REG_GOFFSET_D     0xA5
#define REG_GOFFSET_L     0xA7
#define REG_GOFFSET_R     0xA9
#define REG_GPULSE        0xA6
#define REG_GCONF3        0xAA
#define REG_GCONF4        0xAB
#define REG_GFLVL         0xAE  // Gesture FIFO level
#define REG_GSTATUS       0xAF
#define REG_GFIFO_U       0xFC  // Gesture FIFO data (U/D/L/R)

// Enable register bits
#define EN_PON    0x01  // Power on
#define EN_AEN    0x02  // ALS enable
#define EN_PEN    0x04  // Proximity enable
#define EN_GEN    0x40  // Gesture enable

// Status bits
#define STATUS_GVALID  0x01  // Gesture data valid in FIFO

namespace gesture {

// ── I2C helpers ──────────────────────────────────────────────

static bool writeReg(uint8_t reg, uint8_t val) {
    Wire.beginTransmission(APDS_ADDR);
    Wire.write(reg);
    Wire.write(val);
    return Wire.endTransmission() == 0;
}

static uint8_t readReg(uint8_t reg) {
    Wire.beginTransmission(APDS_ADDR);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)APDS_ADDR, (uint8_t)1);
    return Wire.available() ? Wire.read() : 0;
}

static int readBlock(uint8_t reg, uint8_t* buf, uint8_t len) {
    Wire.beginTransmission(APDS_ADDR);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)APDS_ADDR, len);
    int count = 0;
    while (Wire.available() && count < len) {
        buf[count++] = Wire.read();
    }
    return count;
}

// ── State ────────────────────────────────────────────────────

static bool initialized = false;
static bool gestureEnabled = true;
static bool proximityEnabled = true;

static GestureCallback gestureCb = nullptr;
static ProximityCallback proximityCb = nullptr;
static LightCallback lightCb = nullptr;

static bool wasNear = false;
static uint8_t lastProximity = 0;
static uint16_t lastAmbient = 0;

// Timing
static uint32_t lastPollMs = 0;
static uint32_t lastLightMs = 0;
static constexpr uint32_t POLL_INTERVAL_MS = 50;     // Proximity + gesture: 20Hz
static constexpr uint32_t LIGHT_INTERVAL_MS = 5000;  // Ambient light: every 5s

// Proximity threshold for "near" detection
static constexpr uint8_t PROXIMITY_NEAR_THRESHOLD = 50;
static constexpr uint8_t PROXIMITY_FAR_THRESHOLD = 30;  // Hysteresis

// Gesture detection
static constexpr uint8_t GESTURE_THRESHOLD_ENTER = 40;
static constexpr uint8_t GESTURE_THRESHOLD_EXIT = 30;

// ── Gesture FIFO processing ──────────────────────────────────

struct GestureData {
    uint8_t u, d, l, r;
};

static Type processGestureFifo() {
    uint8_t level = readReg(REG_GFLVL);
    if (level == 0) return Type::NONE;

    // Read all available gesture data (4 bytes per dataset: U, D, L, R)
    GestureData first = {0, 0, 0, 0};
    GestureData last = {0, 0, 0, 0};
    int count = 0;

    for (int i = 0; i < level && i < 32; i++) {
        uint8_t buf[4];
        int read = readBlock(REG_GFIFO_U, buf, 4);
        if (read != 4) break;

        GestureData d = { buf[0], buf[1], buf[2], buf[3] };
        if (count == 0) first = d;
        last = d;
        count++;
    }

    if (count < 4) return Type::WAVE;  // Too few samples — treat as wave

    // Calculate directional deltas
    int ud_first = (int)first.u - (int)first.d;
    int lr_first = (int)first.l - (int)first.r;
    int ud_last  = (int)last.u  - (int)last.d;
    int lr_last  = (int)last.l  - (int)last.r;

    int ud_delta = ud_last - ud_first;
    int lr_delta = lr_last - lr_first;

    // Determine dominant axis
    if (abs(ud_delta) > abs(lr_delta)) {
        if (abs(ud_delta) < 20) return Type::WAVE;  // Too small
        return ud_delta > 0 ? Type::SWIPE_DOWN : Type::SWIPE_UP;
    } else {
        if (abs(lr_delta) < 20) return Type::WAVE;
        return lr_delta > 0 ? Type::SWIPE_RIGHT : Type::SWIPE_LEFT;
    }
}

// ── Public API ───────────────────────────────────────────────

bool init() {
    // Check device ID
    uint8_t id = readReg(REG_ID);
    if (id != 0xAB) {
        Serial.printf("[Gesture] APDS-9960 not found (got 0x%02X, expected 0xAB)\n", id);
        return false;
    }

    // Power off first for clean init
    writeReg(REG_ENABLE, 0x00);
    delay(10);

    // ALS integration time (~100ms)
    writeReg(REG_ATIME, 0xDB);

    // Proximity pulse: 8 pulses, 16us each
    writeReg(REG_PPULSE, 0x87);

    // LED drive 100mA, proximity gain 4x, ALS gain 4x
    writeReg(REG_CONTROL, 0x06);

    // Proximity interrupt thresholds (for interrupt mode — not used but configured)
    writeReg(REG_PILT, 0x00);
    writeReg(REG_PIHT, PROXIMITY_NEAR_THRESHOLD);

    // Gesture config
    writeReg(REG_GPENTH, GESTURE_THRESHOLD_ENTER);
    writeReg(REG_GEXTH, GESTURE_THRESHOLD_EXIT);
    writeReg(REG_GCONF1, 0x40);  // 4 gesture events for INT, 1st dataset after entry
    writeReg(REG_GCONF2, 0x66);  // Gain 4x, LED 100mA, 20ms wait time
    writeReg(REG_GPULSE, 0xC9);  // 32us pulse, 10 pulses
    writeReg(REG_GCONF3, 0x00);  // All photodiodes active
    writeReg(REG_GCONF4, 0x02);  // Gesture FIFO clear, gesture mode enabled

    // Enable: power on + ALS + proximity + gesture
    uint8_t enable = EN_PON | EN_AEN | EN_PEN;
    if (gestureEnabled) enable |= EN_GEN;
    writeReg(REG_ENABLE, enable);

    initialized = true;
    Serial.println("[Gesture] APDS-9960 initialized (proximity + gesture + ambient light)");
    return true;
}

void onGesture(GestureCallback cb) { gestureCb = cb; }
void onProximity(ProximityCallback cb) { proximityCb = cb; }
void onLight(LightCallback cb) { lightCb = cb; }

void tick(uint32_t nowMs) {
    if (!initialized) return;

    // ── Gesture check (highest priority) ─────────────────
    if (gestureEnabled && (nowMs - lastPollMs >= POLL_INTERVAL_MS)) {
        lastPollMs = nowMs;

        // Check if gesture data is available
        uint8_t gstatus = readReg(REG_GSTATUS);
        if (gstatus & STATUS_GVALID) {
            Type g = processGestureFifo();
            if (g != Type::NONE && gestureCb) {
                gestureCb(g);
            }
        }

        // ── Proximity check ──────────────────────────────
        if (proximityEnabled) {
            lastProximity = readReg(REG_PDATA);

            bool isCurrentlyNear = wasNear
                ? (lastProximity > PROXIMITY_FAR_THRESHOLD)    // Already near — use lower threshold to leave
                : (lastProximity > PROXIMITY_NEAR_THRESHOLD);  // Was far — use higher threshold to enter

            if (isCurrentlyNear != wasNear) {
                wasNear = isCurrentlyNear;
                if (proximityCb) proximityCb(wasNear);
            }
        }
    }

    // ── Ambient light (less frequent) ────────────────────
    if (nowMs - lastLightMs >= LIGHT_INTERVAL_MS) {
        lastLightMs = nowMs;
        uint8_t lo = readReg(REG_CDATAL);
        uint8_t hi = readReg(REG_CDATAH);
        uint16_t raw = (hi << 8) | lo;

        // Simple lux approximation (not calibrated, but useful for relative changes)
        uint16_t lux = raw;  // 1:1 for now, calibrate on real hardware
        if (lux != lastAmbient) {
            lastAmbient = lux;
            if (lightCb) lightCb(lux);
        }
    }
}

uint8_t getProximity() { return lastProximity; }
uint16_t getAmbientLight() { return lastAmbient; }
bool isNear() { return wasNear; }

void setGestureEnabled(bool enabled) {
    gestureEnabled = enabled;
    if (!initialized) return;
    uint8_t reg = readReg(REG_ENABLE);
    if (enabled) reg |= EN_GEN;
    else reg &= ~EN_GEN;
    writeReg(REG_ENABLE, reg);
}

void setProximityEnabled(bool enabled) {
    proximityEnabled = enabled;
}

}  // namespace gesture
