# Battery Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read the LiPo battery voltage from GPIO9, show percentage on-device (BIOS + status bar), trigger low-battery LED + voice alert, auto-dim on low power, and push battery level to the backend so the Flutter app can display it.

**Architecture:** A new `battery.cpp/.h` module owns all ADC reading and percentage math. It exposes a simple polling API called every 30s from the main loop. Low-battery side effects (LED override, voice alert, power saving) are triggered from the main loop based on thresholds. Battery level is piggy-backed onto the existing `device:info` WebSocket event so the backend and Flutter app get it with zero new event types.

**Tech Stack:** ESP32-S3 Arduino ADC (`analogRead` + `analogSetAttenuation`), NestJS WebSocket gateway (`audio.gateway.ts`), Flutter `DevicesBloc`.

---

## Scope

This plan covers:
1. Firmware `battery.cpp/.h` — ADC read, smoothing, voltage→%, USB detection
2. Firmware wiring — `main.cpp` periodic read, `updateStatusBar()`, low-battery triggers
3. Low-battery LED override (already in `status_led`, just needs wiring)
4. Low-battery voice alert via `resilience_audio`
5. Auto power saving (dim display) below 20%
6. WebSocket push via extended `device:info` event
7. Backend handler update (`audio.gateway.ts`)
8. Flutter battery display on device detail page

---

## File Map

| File | Action | What changes |
|------|--------|--------------|
| `firmware/src/battery.cpp` | **Create** | ADC read, multi-sample average, voltage→%, USB detection |
| `firmware/include/battery.h` | **Create** | Public API: `init()`, `readPercent()`, `isUsbPowered()`, `isLow()`, `isCritical()` |
| `firmware/src/main.cpp` | **Modify** | Periodic battery read, wire into `updateStatusBar()`, low-battery triggers |
| `firmware/include/resilience_audio.h` | **Modify** | Add `LOW_BATTERY` clip enum value |
| `firmware/src/resilience_audio.cpp` | **Modify** | Add `LOW_BATTERY` clip filename mapping |
| `backend/src/modules/gateway/audio.gateway.ts` | **Modify** | `onDeviceInfo()` — add `batteryPercent` field, log it |
| `backend/src/modules/gateway/session.manager.ts` | **Modify** | Add `batteryPercent` to session state |
| `app/lib/features/devices/data/models/device_model.dart` | **Modify** | Add `batteryPercent` field (nullable) |
| `app/lib/features/devices/presentation/pages/device_detail_page.dart` | **Modify** | Show battery % in status bar widget |

---

## Hardware Notes

**Voltage divider:** The Hosyond ESP32-S3 board uses a 1:2 resistor divider (two equal resistors ~100K) on GPIO9. This halves the battery voltage before it reaches the ADC pin:

```
battery_voltage = adc_voltage * 2
adc_voltage     = adc_raw / 4095.0 * 3.3
```

**ADC attenuation:** GPIO9 must use `ADC_11db` attenuation to read up to ~3.1V at the pin (= ~6.2V battery — well above 4.2V LiPo max).

**USB detection:** When USB is charging, the battery voltage typically reads ≥ 4.1V. Use this as the USB threshold. Note: there is no explicit charge-detect pin on this board, so voltage is the only signal.

**LiPo discharge curve (simplified):**

| Battery voltage | Approximate % |
|-----------------|---------------|
| ≥ 4.1V          | USB / Charging |
| 4.05V           | 100% |
| 3.90V           | 75%  |
| 3.75V           | 50%  |
| 3.60V           | 25%  |
| 3.50V           | 10%  |
| ≤ 3.40V         | 0%   |

**Calibration note:** ESP32 ADC is noisy and non-linear. The voltage divider ratio on your specific board should be verified by measuring battery voltage with a multimeter and comparing against the computed value. A `BATTERY_SCALE` constant is exposed in `battery.h` for easy tuning.

---

## Task 1: `battery.h` / `battery.cpp` — ADC module

**Files:**
- Create: `firmware/include/battery.h`
- Create: `firmware/src/battery.cpp`

- [ ] **Step 1: Create `battery.h`**

```cpp
// firmware/include/battery.h
#pragma once
#include <cstdint>

/// Battery monitoring via GPIO9 ADC.
///
/// Reads LiPo voltage through the board's 1:2 voltage divider.
/// Call init() once at boot, then readPercent() periodically (every 30s is fine).
///
/// Calibration: if the reported voltage doesn't match a multimeter reading,
/// adjust BATTERY_SCALE in battery.cpp.
namespace battery {

/// Thresholds (percent).
static constexpr uint8_t LOW_THRESHOLD      = 20;  // trigger LED + voice alert
static constexpr uint8_t CRITICAL_THRESHOLD = 10;  // trigger auto power saving

/// One-time setup. Must be called before readPercent().
void init();

/// Sample the ADC, average 16 readings, and return battery percentage (0-100).
/// Returns 255 if USB power is detected (voltage ≥ 4.1V).
uint8_t readPercent();

/// True if the last reading detected USB charging voltage (≥ 4.1V).
bool isUsbPowered();

/// True if last reading was ≤ LOW_THRESHOLD.
bool isLow();

/// True if last reading was ≤ CRITICAL_THRESHOLD.
bool isCritical();

/// Last computed voltage in millivolts (for BIOS diagnostics).
uint16_t lastVoltageMillivolts();

}  // namespace battery
```

- [ ] **Step 2: Create `battery.cpp`**

```cpp
// firmware/src/battery.cpp
#include "battery.h"
#include <Arduino.h>
#include <driver/adc.h>

// ── Calibration ────────────────────────────────────────────
// Adjust if computed voltage doesn't match a multimeter reading.
// Default 2.0 = 1:2 divider (two equal resistors on the board).
static constexpr float BATTERY_SCALE    = 2.0f;
static constexpr float ADC_REF_VOLTS    = 3.3f;
static constexpr int   ADC_MAX          = 4095;
static constexpr float USB_VOLTAGE_MIN  = 4100.0f;  // mV — above this = USB powered

// ── LiPo discharge curve (voltage mV → percent) ────────────
// Piecewise linear between these breakpoints.
static const struct { uint16_t mv; uint8_t pct; } CURVE[] = {
    { 4050, 100 },
    { 3900,  75 },
    { 3750,  50 },
    { 3600,  25 },
    { 3500,  10 },
    { 3400,   0 },
};
static constexpr int CURVE_LEN = sizeof(CURVE) / sizeof(CURVE[0]);

// ── State ───────────────────────────────────────────────────
static uint8_t  lastPercent   = 255;
static uint16_t lastMv        = 0;
static bool     usbPowered    = false;

static uint8_t voltageToPercent(uint16_t mv) {
    if (mv >= CURVE[0].mv) return 100;
    if (mv <= CURVE[CURVE_LEN - 1].mv) return 0;
    for (int i = 0; i < CURVE_LEN - 1; i++) {
        if (mv <= CURVE[i].mv && mv >= CURVE[i + 1].mv) {
            float t = (float)(mv - CURVE[i + 1].mv) /
                      (float)(CURVE[i].mv - CURVE[i + 1].mv);
            return (uint8_t)(CURVE[i + 1].pct + t * (CURVE[i].pct - CURVE[i + 1].pct));
        }
    }
    return 0;
}

void battery::init() {
    // GPIO9 = ADC1 channel 8 on ESP32-S3
    analogSetPinAttenuation(BATTERY_ADC, ADC_11db);
    Serial.println("[Battery] Init — GPIO9 ADC, 11dB attenuation");
}

uint8_t battery::readPercent() {
    // Average 16 samples to reduce ADC noise
    uint32_t sum = 0;
    for (int i = 0; i < 16; i++) {
        sum += analogRead(BATTERY_ADC);
        delayMicroseconds(100);
    }
    uint32_t raw = sum / 16;

    float adcVolts = (float)raw / ADC_MAX * ADC_REF_VOLTS;
    float batVolts = adcVolts * BATTERY_SCALE;
    lastMv = (uint16_t)(batVolts * 1000.0f);

    if (lastMv >= (uint16_t)USB_VOLTAGE_MIN) {
        usbPowered  = true;
        lastPercent = 255;
        Serial.printf("[Battery] USB powered (%u mV)\n", lastMv);
        return 255;
    }

    usbPowered  = false;
    lastPercent = voltageToPercent(lastMv);
    Serial.printf("[Battery] %u mV → %u%%\n", lastMv, lastPercent);
    return lastPercent;
}

bool     battery::isUsbPowered()          { return usbPowered; }
bool     battery::isLow()                 { return !usbPowered && lastPercent != 255 && lastPercent <= LOW_THRESHOLD; }
bool     battery::isCritical()            { return !usbPowered && lastPercent != 255 && lastPercent <= CRITICAL_THRESHOLD; }
uint16_t battery::lastVoltageMillivolts() { return lastMv; }
```

- [ ] **Step 3: Verify it compiles**

```bash
cd firmware && pio run 2>&1 | grep -E "error:|warning:|SUCCESS"
```

Expected: `SUCCESS` with no errors. Warnings about unused variables in other files are fine.

- [ ] **Step 4: Commit**

```bash
git add firmware/include/battery.h firmware/src/battery.cpp
git commit -m "feat(firmware): add battery ADC module — GPIO9 read, voltage-to-%, USB detection"
```

---

## Task 2: Wire battery into `main.cpp`

**Files:**
- Modify: `firmware/src/main.cpp`

- [ ] **Step 1: Add `#include "battery.h"` near the top of `main.cpp`** (after existing includes)

```cpp
#include "battery.h"
```

- [ ] **Step 2: Call `battery::init()` in `setup()`**

Find the block where other modules are initialized (look for `power_manager::init`, `status_led::init`, etc.) and add `battery::init()` nearby:

```cpp
battery::init();
```

- [ ] **Step 3: Replace hardcoded `255` in `updateStatusBar()`**

```cpp
// Before:
sb.batteryPercent = 255;  // USB-powered

// After:
sb.batteryPercent = battery::readPercent();  // 255 = USB, 0-100 = battery level
```

> **Note:** `readPercent()` averages 16 ADC samples (~1.6ms). This is called every frame in `updateStatusBar()` which runs in `loop()`. To avoid calling ADC on every frame, add a 30s throttle:

```cpp
// In updateStatusBar(), replace the single line above with:
static uint32_t lastBatReadMs = 0;
static uint8_t  cachedBatPct  = 255;
if (millis() - lastBatReadMs > 30000) {
    cachedBatPct   = battery::readPercent();
    lastBatReadMs  = millis();
}
sb.batteryPercent = cachedBatPct;
```

- [ ] **Step 4: Build and flash**

```bash
pio run -t upload && pio device monitor --baud 115200
```

Expected serial output within 30s of boot:
```
[Battery] Init — GPIO9 ADC, 11dB attenuation
[Battery] 3842 mV → 63%
```
(Exact voltage will vary. If it reads `USB powered` while on battery, adjust `USB_VOLTAGE_MIN` in `battery.cpp`.)

- [ ] **Step 5: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(firmware): wire battery reads into status bar — 30s polling, cached percent"
```

---

## Task 3: Low-battery voice alert

**Files:**
- Modify: `firmware/include/resilience_audio.h`
- Modify: `firmware/src/resilience_audio.cpp`
- Modify: `firmware/src/main.cpp`

- [ ] **Step 1: Add `LOW_BATTERY` clip to the enum in `resilience_audio.h`**

```cpp
// In the Clip enum, after WAKE:
WAKE,           // Waking up sound
LOW_BATTERY,    // "Hey, I'm running low — plug me in"
```

- [ ] **Step 2: Add `LOW_BATTERY` to the filename mapping in `resilience_audio.cpp`**

Find `clipFileName()` — it's a switch/if-chain mapping `Clip` → filename string. Add:

```cpp
case Clip::LOW_BATTERY: return "low_battery.opus";
```

Also add it to `init()` where clips are loaded (same pattern as the existing clips — it reads the filename from `clipFileName()` automatically if the function is used in a loop, otherwise add it explicitly).

- [ ] **Step 3: Add low-battery alert trigger in `main.cpp`**

In the main `loop()` or alongside the battery read throttle, add a one-shot alert tracker:

```cpp
// After the battery read block in updateStatusBar() or loop():
static bool lowBatAlertFired = false;
if (battery::isLow() && !lowBatAlertFired && appState.botState == BotState::IDLE) {
    lowBatAlertFired = true;
    resilience_audio::playClip(resilience_audio::Clip::LOW_BATTERY);
    Serial.println("[Battery] Low battery alert fired");
}
// Reset alert if battery recovers (plugged in)
if (battery::isUsbPowered()) {
    lowBatAlertFired = false;
}
```

- [ ] **Step 4: Generate the audio file**

Use ElevenLabs to generate `low_battery.opus` with the Ziggy voice. Prompt for the TTS generation:

```
"Hey, I'm running low on battery — plug me in before I pass out."
```

Save as `low_battery.opus` in the correct format (Opus, 16kHz mono) and place it at `/audio/resilience/low_battery.opus` on the SD card.

- [ ] **Step 5: Build and verify**

```bash
pio run -t upload && pio device monitor --baud 115200
```

Drain the battery below 20% (or temporarily lower `LOW_THRESHOLD` to 90 for testing) and confirm the alert fires once, and resets when plugged into USB.

- [ ] **Step 6: Commit**

```bash
git add firmware/include/resilience_audio.h firmware/src/resilience_audio.cpp firmware/src/main.cpp
git commit -m "feat(firmware): add low-battery voice alert via resilience_audio"
```

---

## Task 4: Low-battery LED + auto power saving

**Files:**
- Modify: `firmware/src/main.cpp`

The `status_led` module already has a low-battery pattern defined (orange fast blink). It just needs to be activated. The `power_manager` already supports brightness reduction.

- [ ] **Step 1: Trigger low-battery LED override**

In `main.cpp`, in the same battery threshold block from Task 3, add LED override:

```cpp
if (battery::isLow() && !battery::isUsbPowered()) {
    status_led::setLowBattery(true);   // orange fast blink override
} else {
    status_led::setLowBattery(false);  // restore normal BotState sync
}
```

Check `status_led.h` for the exact function signature — it may be `setOverride(Pattern::LOW_BATTERY)` or similar. Match the existing API.

- [ ] **Step 2: Auto-dim display on critical battery**

```cpp
static bool criticalDimApplied = false;
if (battery::isCritical() && !criticalDimApplied) {
    criticalDimApplied = true;
    // Drop active brightness to 30% to extend runtime
    power_manager::Config cfg = {};
    cfg.activeBrightness = 30;
    cfg.dimBrightness    = 10;
    cfg.dimTimeoutSec    = 15;   // dim faster when critical
    cfg.sleepTimeoutSec  = 60;   // sleep sooner
    power_manager::updateConfig(cfg);
    Serial.println("[Battery] Critical — power saving mode active");
}
if (battery::isUsbPowered() && criticalDimApplied) {
    criticalDimApplied = false;
    power_manager::updateConfig(power_manager::Config{});  // restore defaults
}
```

- [ ] **Step 3: Build and verify**

```bash
pio run -t upload
```

Temporarily lower `CRITICAL_THRESHOLD` to 90 and verify the display dims and LED turns orange. Restore threshold after testing.

- [ ] **Step 4: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(firmware): low-battery LED override and auto power saving on critical"
```

---

## Task 5: Push battery to backend via `device:info`

**Files:**
- Modify: `firmware/src/main.cpp`

The firmware already sends `device:info` periodically. Extend the payload to include `batteryPercent`.

- [ ] **Step 1: Find where `device:info` is sent in `main.cpp`**

Search for `"device:info"` in `main.cpp`. It builds a JSON payload with `firmwareVersion`, `wifiSsid`, `wifiRssi`, etc. Add `batteryPercent` to that payload:

```cpp
// In the device:info JSON build, add:
snprintf(buf, sizeof(buf),
    "{\"firmwareVersion\":\"%s\",\"wifiSsid\":\"%s\",\"wifiRssi\":%d,"
    "\"ip\":\"%s\",\"uptimeSec\":%lu,\"freeHeap\":%lu,"
    "\"sdMounted\":%s,\"batteryPercent\":%d}",
    FIRMWARE_VERSION,
    WiFi.SSID().c_str(),
    (int)WiFi.RSSI(),
    WiFi.localIP().toString().c_str(),
    millis() / 1000,
    (unsigned long)ESP.getFreeHeap(),
    sd_storage::isMounted() ? "true" : "false",
    (int)battery::readPercent()   // 255 = USB
);
```

- [ ] **Step 2: Build and verify in serial monitor**

```bash
pio run -t upload && pio device monitor --baud 115200
```

Look for `device:info` JSON in serial output and confirm `batteryPercent` is present.

- [ ] **Step 3: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(firmware): include batteryPercent in device:info WS event"
```

---

## Task 6: Backend — handle `batteryPercent` in `device:info`

**Files:**
- Modify: `backend/src/modules/gateway/audio.gateway.ts`
- Modify: `backend/src/modules/gateway/session.manager.ts`

- [ ] **Step 1: Update `onDeviceInfo()` in `audio.gateway.ts`**

```typescript
// In onDeviceInfo(), update the updateDeviceInfo call and log:
private onDeviceInfo(deviceId: string, data: any) {
  if (!data) return;
  this.persistence.updateDeviceInfo(deviceId, {
    firmwareVersion: data.firmwareVersion,
    wifiSsid: data.wifiSsid,
    wifiRssi: data.wifiRssi,
  }).catch((err) =>
    this.logger.warn(`Failed to save device info: ${err.message}`),
  );

  // Cache battery percent in session for Flutter polling
  const session = this.sessions.get(deviceId);
  if (session && data.batteryPercent !== undefined) {
    session.batteryPercent = data.batteryPercent as number;
  }

  this.logger.log(
    `Device ${deviceId} info: fw=${data.firmwareVersion} wifi=${data.wifiSsid} rssi=${data.wifiRssi}` +
    ` ip=${data.ip ?? '-'} uptime=${data.uptimeSec ?? '-'}s heap=${data.freeHeap ?? '-'}` +
    ` sd=${data.sdMounted ?? '-'} battery=${data.batteryPercent ?? '-'}`,
  );
}
```

- [ ] **Step 2: Add `batteryPercent` to the session type in `session.manager.ts`**

Find the session interface/type definition and add:

```typescript
batteryPercent?: number;  // 0-100, or 255 = USB powered, undefined = unknown
```

- [ ] **Step 3: Expose battery in the device stats endpoint**

In `devices.controller.ts` or wherever `GET /devices/:id/stats` is handled, include the battery percent from the session:

```typescript
// In the stats handler, add to the response:
batteryPercent: this.sessions.get(deviceId)?.batteryPercent ?? null,
```

- [ ] **Step 4: Run backend tests**

```bash
cd backend && npm test 2>&1 | tail -20
```

Expected: all existing tests pass (no new tests needed — this is a pass-through field).

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/gateway/audio.gateway.ts backend/src/modules/gateway/session.manager.ts
git commit -m "feat(backend): persist batteryPercent from device:info into session and stats endpoint"
```

---

## Task 7: Flutter — show battery in device detail

**Files:**
- Modify: `app/lib/features/devices/data/models/device_model.dart` (or wherever device stats are modeled)
- Modify: `app/lib/features/devices/presentation/pages/device_detail_page.dart`

- [ ] **Step 1: Add `batteryPercent` to the stats model**

Find the stats model (likely a `DeviceStats` or similar class in `data/models/`). Add:

```dart
final int? batteryPercent;  // 0-100, 255 = USB, null = unknown
```

Update `fromJson`:
```dart
batteryPercent: json['batteryPercent'] as int?,
```

- [ ] **Step 2: Add a battery widget to the device detail status bar**

In `device_detail_page.dart`, find the compact status bar section (shows online/offline, Wi-Fi SSID, uptime). Add a battery indicator:

```dart
// Battery indicator helper
Widget _buildBatteryIndicator(int? pct) {
  if (pct == null) return const SizedBox.shrink();
  if (pct == 255) {
    return const Row(children: [
      Icon(Icons.usb, size: 14),
      SizedBox(width: 4),
      Text('Charging', style: TextStyle(fontSize: 12)),
    ]);
  }
  final icon = pct > 60 ? Icons.battery_full
      : pct > 30 ? Icons.battery_3_bar
      : Icons.battery_alert;
  final color = pct <= 20 ? Colors.red : null;
  return Row(children: [
    Icon(icon, size: 14, color: color),
    const SizedBox(width: 4),
    Text('$pct%', style: TextStyle(fontSize: 12, color: color)),
  ]);
}
```

Call `_buildBatteryIndicator(stats?.batteryPercent)` in the status bar row.

- [ ] **Step 3: Run Flutter tests**

```bash
cd app && flutter test 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 4: Run static analysis**

```bash
flutter analyze 2>&1 | grep -E "error|warning" | head -20
```

Expected: zero issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/devices/
git commit -m "feat(app): show battery percentage in device detail status bar"
```

---

## Implementation Status (April 2026)

All 7 code tasks are **complete and merged**:

| Task | What | Status |
|------|------|--------|
| 1 | `battery.h` / `battery.cpp` — ADC module | ✅ Done |
| 2 | `main.cpp` — 30s polling, status bar wiring | ✅ Done |
| 3 | `resilience_audio` + low-battery voice alert | ✅ Done |
| 4 | LED override in `syncFaceToState()` + critical power saving | ✅ Done |
| 5 | `device:info` WS event extended with `batteryPercent` | ✅ Done |
| 6 | Backend session + stats endpoint updated | ✅ Done |
| 7 | Flutter `DeviceStats` model + battery indicator in status bar | ✅ Done |

**Blocked on hardware:** The board uses a **1.25mm 2P socket** (not JST PH 2.0 as originally documented). The battery's existing connector does not fit. Need a battery with a 1.25mm 2P plug, or a JST SH 1.25mm adapter cable.

### What's left once the connector issue is resolved

1. **Connect the battery** — requires 1.25mm 2P plug (JST SH 1.25mm). Watch polarity.

2. **Flash the firmware** (code is already written):
   ```bash
   cd firmware && pio run -t upload
   ```

3. **Check serial output** within 30s of boot:
   ```
   [Battery] Init — GPIO9 ADC, 11dB attenuation
   [Battery] 3842 mV → 63%
   ```
   Or if USB is also connected: `[Battery] USB powered (4350 mV)`

4. **Calibrate ADC** — measure actual battery voltage with a multimeter, compare to serial output. If they differ by more than ~100mV, adjust `BATTERY_SCALE` in `battery.cpp`:
   - Reads too low → increase slightly above `2.0f`
   - Reads too high → decrease it

5. **Generate `low_battery.opus`** — use ElevenLabs (Ziggy voice), Opus 16kHz mono, place at `/audio/resilience/low_battery.opus` on the SD card. Without this file the voice alert silently skips (no crash).

6. **Test low-battery alert** — temporarily set `LOW_THRESHOLD = 90` in `battery.h`, reflash, confirm orange LED + voice clip fires, resets on USB plug. Restore to `20` after.

---

## What's Not In This Plan

- **Deep sleep on critical battery** — requires verifying wake sources on real hardware first (touch INT on GPIO17). Tracked in `16-hardware-capabilities.md §3.7`.
- **Battery percentage history / graphs** — not needed for V1.
- **Charge status LED on the board itself** — the board has a hardware charge LED, no firmware needed.
