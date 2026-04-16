# Smart Battery Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add proper battery indicator colors on ESP32 display, battery discharge estimation, battery history chart in Flutter app, and critical deep sleep with goodnight TTS.

**Architecture:** Firmware tracks discharge rate via rolling mV window and enters ESP32-S3 deep sleep (ext0 wake on GPIO17 touch INT) at critical battery. Backend stores a rolling 24h battery history ring buffer in the session. Flutter app renders a small line chart via fl_chart on the device detail page.

**Tech Stack:** ESP-IDF esp_sleep API, fl_chart (Flutter), existing NestJS session manager, LovyanGFX display rendering.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `firmware/src/display.cpp` | Modify | Fix battery indicator colors (green/yellow/red/blink) |
| `firmware/src/battery.cpp` | Modify | Add discharge rate tracking, minutes remaining calc |
| `firmware/include/battery.h` | Modify | Expose `minutesRemaining()` API |
| `firmware/src/main.cpp` | Modify | Add `batteryMinutesRemaining` to device:info, deep sleep trigger logic, goodnight TTS |
| `firmware/include/resilience_audio.h` | Modify | Add CRITICAL_SHUTDOWN clip enum |
| `firmware/src/resilience_audio.cpp` | Modify | Add critical_shutdown.opus mapping |
| `firmware/src/power_manager.cpp` | Modify | Add `enterDeepSleep()` function |
| `firmware/include/power_manager.h` | Modify | Expose `enterDeepSleep()` |
| `backend/src/modules/gateway/session.manager.ts` | Modify | Add battery history ring buffer to session |
| `backend/src/modules/gateway/audio.gateway.ts` | Modify | Store history entries on device:info |
| `backend/src/modules/devices/devices.service.ts` | Modify | Return battery history + minutes remaining in stats |
| `app/lib/features/devices/data/models/device_stats_model.dart` | Modify | Add batteryHistory + minutesRemaining fields |
| `app/lib/features/devices/presentation/pages/device_detail_page.dart` | Modify | Add battery history chart card + time remaining display |
| `app/pubspec.yaml` | Modify | Add fl_chart dependency |

---

## Task 1: Fix battery indicator colors on ESP32 display

**Files:**
- Modify: `firmware/src/display.cpp:1598-1627`

The current battery indicator uses accent-dimmed fill for normal levels. Update to use proper color coding: green for full/charging, yellow for medium, red for low with blinking.

- [ ] **Step 1: Update the battery indicator rendering in renderFace()**

Replace the battery indicator block (lines 1598-1627) in `firmware/src/display.cpp` with:

```cpp
    // ── Battery indicator (top-right corner) ───────────────────
    // Tiny battery icon: 16x9 outline with fill proportional to charge.
    // Color scheme: green=full/charging, yellow=medium, red=low (blinks).
    {
        const int bx = LCD_WIDTH - 20;
        const int by = 4;
        const int bw = 16, bh = 9;
        const int nubW = 2, nubH = 5;
        uint8_t pct = status.batteryPercent;
        bool isCharging = (pct == 255);

        // Determine fill color based on level
        uint16_t fillCol, outCol;
        if (isCharging) {
            fillCol = rgb(0, 200, 80);    // green
            outCol  = rgb(0, 120, 50);    // dim green outline
        } else if (pct > 80) {
            fillCol = rgb(0, 200, 80);    // green
            outCol  = rgb(0, 120, 50);
        } else if (pct > 40) {
            fillCol = rgb(255, 255, 255); // white
            outCol  = blendRGB565(pal.accent, pal.bg, 80);
        } else if (pct > 20) {
            fillCol = rgb(220, 180, 0);   // yellow
            outCol  = rgb(130, 110, 0);
        } else {
            fillCol = rgb(220, 50, 40);   // red
            outCol  = rgb(140, 30, 25);
        }

        // Low battery blink: <=20% slow (1s), <=10% fast (500ms)
        bool blinkOff = false;
        if (!isCharging && pct <= 20) {
            uint32_t period = (pct <= 10) ? 500 : 1000;
            blinkOff = ((millis() / period) % 2 != 0);
        }

        // Draw outline + nub
        s.drawRect(bx, by, bw, bh, outCol);
        s.fillRect(bx + bw, by + (bh - nubH) / 2, nubW, nubH, outCol);

        // Draw fill
        int fillMax = bw - 2;
        if (!blinkOff) {
            if (isCharging) {
                // Pulsing green fill
                float pulse = sinf(millis() / 600.0f) * 0.3f + 0.7f;
                int fw = (int)(fillMax * pulse);
                s.fillRect(bx + 1, by + 1, fw, bh - 2, fillCol);
            } else {
                int fw = (pct > 100) ? fillMax : (fillMax * pct / 100);
                if (fw < 1 && pct > 0) fw = 1;
                s.fillRect(bx + 1, by + 1, fw, bh - 2, fillCol);
            }
        }
    }
```

- [ ] **Step 2: Build firmware**

Run: `pio run`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add firmware/src/display.cpp
git commit -m "fix(display): proper battery indicator colors — green/yellow/red with blink"
```

---

## Task 2: Add discharge rate tracking and minutes remaining

**Files:**
- Modify: `firmware/src/battery.cpp`
- Modify: `firmware/include/battery.h`

Track a rolling window of the last 10 voltage readings (5 minutes at 30s intervals). Calculate mV/min drain rate and extrapolate time to empty.

- [ ] **Step 1: Add rolling window and minutesRemaining to battery.h**

Add after the existing function declarations in `battery.h`:

```cpp
/// Estimated minutes of battery remaining based on discharge rate.
/// Returns -1 if charging, unknown, or insufficient data.
int16_t minutesRemaining();
```

- [ ] **Step 2: Implement discharge rate tracking in battery.cpp**

Add after the module state variables section:

```cpp
// ── Discharge rate tracking ──────────────────────────────────────────────────
static constexpr int RATE_WINDOW = 10;           // samples (5 min at 30s intervals)
static uint16_t rateBuffer[RATE_WINDOW] = {};    // circular buffer of mV readings
static int rateIndex = 0;
static int rateSamples = 0;                       // how many samples we've collected
```

At the end of `readPercent()`, before the final `return lastPercent;`, add:

```cpp
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
```

Add the `minutesRemaining()` function before the closing namespace brace:

```cpp
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
```

- [ ] **Step 3: Build firmware**

Run: `pio run`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git add firmware/src/battery.cpp firmware/include/battery.h
git commit -m "feat(battery): discharge rate tracking with minutes remaining estimate"
```

---

## Task 3: Add minutesRemaining to device:info payload

**Files:**
- Modify: `firmware/src/main.cpp` (the `sendDeviceInfo()` function)

- [ ] **Step 1: Update sendDeviceInfo() to include minutesRemaining**

In `sendDeviceInfo()` in `main.cpp`, update the JSON payload. Change the format string and args to include the new field:

```cpp
static void sendDeviceInfo() {
    char infoPayload[384];
    snprintf(infoPayload, sizeof(infoPayload),
        "{"
        "\"firmwareVersion\":\"%s\","
        "\"wifiSsid\":\"%s\","
        "\"wifiRssi\":%d,"
        "\"ip\":\"%s\","
        "\"uptimeSec\":%lu,"
        "\"freeHeap\":%lu,"
        "\"sdMounted\":%s,"
        "\"batteryPercent\":%d,"
        "\"batteryMv\":%u,"
        "\"batteryCharging\":%s,"
        "\"batteryMinutesRemaining\":%d"
        "}",
        FIRMWARE_VERSION,
        WiFi.SSID().c_str(),
        WiFi.RSSI(),
        WiFi.localIP().toString().c_str(),
        millis() / 1000,
        (unsigned long)ESP.getFreeHeap(),
        sd_storage::isMounted() ? "true" : "false",
        (int)battery::readPercent(),
        (unsigned)battery::lastVoltageMillivolts(),
        battery::isCharging() ? "true" : "false",
        (int)battery::minutesRemaining()
    );
    ws_client::sendEvent("device:info", infoPayload);
}
```

- [ ] **Step 2: Build firmware**

Run: `pio run`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(battery): send minutesRemaining in device:info payload"
```

---

## Task 4: Backend — battery history ring buffer and minutes remaining

**Files:**
- Modify: `backend/src/modules/gateway/session.manager.ts`
- Modify: `backend/src/modules/gateway/audio.gateway.ts`
- Modify: `backend/src/modules/devices/devices.service.ts`

Store a rolling 24h history of battery readings in the session, and pass through minutesRemaining.

- [ ] **Step 1: Add history types and fields to session.manager.ts**

Add the history type before the `DeviceSession` interface:

```typescript
export interface BatteryHistoryEntry {
  timestamp: number; // Unix ms
  percent: number;   // 0-100 or 255
  mv: number;
  charging: boolean;
}
```

Add to the `DeviceSession` interface:

```typescript
  /** Rolling battery history — last 24h of readings, one per minute. */
  batteryHistory: BatteryHistoryEntry[];
  /** Estimated minutes remaining from firmware discharge rate. */
  batteryMinutesRemaining?: number;
```

In the `SessionManager.createSession()` method (or wherever sessions are initialized), ensure `batteryHistory` defaults to `[]`.

- [ ] **Step 2: Update audio.gateway.ts to store history entries**

In the `onDeviceInfo()` method, after storing `batteryMv` and `batteryCharging`, add:

```typescript
      if (data.batteryMinutesRemaining !== undefined)
        session.batteryMinutesRemaining = data.batteryMinutesRemaining as number;

      // Append to battery history (max 1440 entries = 24h at 1/min)
      if (data.batteryPercent !== undefined && data.batteryMv !== undefined) {
        session.batteryHistory.push({
          timestamp: Date.now(),
          percent: data.batteryPercent as number,
          mv: data.batteryMv as number,
          charging: (data.batteryCharging as boolean) ?? false,
        });
        // Keep last 24h (1440 entries at ~1 entry/min)
        if (session.batteryHistory.length > 1440) {
          session.batteryHistory = session.batteryHistory.slice(-1440);
        }
      }
```

Update the log line to include minutesRemaining:

```typescript
    this.logger.log(
      `Device ${deviceId} info: fw=${data.firmwareVersion} wifi=${data.wifiSsid} rssi=${data.wifiRssi} ip=${data.ip ?? '-'} uptime=${data.uptimeSec ?? '-'}s heap=${data.freeHeap ?? '-'} sd=${data.sdMounted ?? '-'} battery=${data.batteryPercent ?? '-'}% ${data.batteryMv ?? '-'}mV charging=${data.batteryCharging ?? '-'} remaining=${data.batteryMinutesRemaining ?? '-'}min`,
    );
```

- [ ] **Step 3: Update devices.service.ts to return history and minutes remaining**

In the `getStats()` return object, add:

```typescript
      batteryMinutesRemaining: this.sessionManager.get(id)?.batteryMinutesRemaining ?? null,
      batteryHistory: this.sessionManager.get(id)?.batteryHistory ?? [],
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/modules/gateway/session.manager.ts backend/src/modules/gateway/audio.gateway.ts backend/src/modules/devices/devices.service.ts
git commit -m "feat(battery): backend battery history ring buffer and minutes remaining"
```

---

## Task 5: Flutter — add fl_chart dependency and update model

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/features/devices/data/models/device_stats_model.dart`

- [ ] **Step 1: Add fl_chart to pubspec.yaml**

Add under dependencies:

```yaml
  fl_chart: ^0.70.2
```

Run: `flutter pub get`

- [ ] **Step 2: Update DeviceStats model**

Add new fields to `DeviceStats`:

```dart
class DeviceStats {
  final int conversationsToday;
  final int totalConversations;
  final int totalMemories;
  final int poolSize;
  final int? batteryPercent;
  final int? batteryMv;
  final bool? batteryCharging;
  final int? batteryMinutesRemaining; // -1 = unknown, 0+ = minutes
  final List<BatteryHistoryEntry> batteryHistory;

  const DeviceStats({
    required this.conversationsToday,
    required this.totalConversations,
    required this.totalMemories,
    required this.poolSize,
    this.batteryPercent,
    this.batteryMv,
    this.batteryCharging,
    this.batteryMinutesRemaining,
    this.batteryHistory = const [],
  });

  factory DeviceStats.fromJson(Map<String, dynamic> json) {
    return DeviceStats(
      conversationsToday: json['conversationsToday'] as int? ?? 0,
      totalConversations: json['totalConversations'] as int? ?? 0,
      totalMemories: json['totalMemories'] as int? ?? 0,
      poolSize: json['poolSize'] as int? ?? 0,
      batteryPercent: json['batteryPercent'] as int?,
      batteryMv: json['batteryMv'] as int?,
      batteryCharging: json['batteryCharging'] as bool?,
      batteryMinutesRemaining: json['batteryMinutesRemaining'] as int?,
      batteryHistory: (json['batteryHistory'] as List<dynamic>?)
              ?.map((e) => BatteryHistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  // Keep existing copyWith but add new fields...
}

class BatteryHistoryEntry {
  final DateTime timestamp;
  final int percent;
  final int mv;
  final bool charging;

  const BatteryHistoryEntry({
    required this.timestamp,
    required this.percent,
    required this.mv,
    required this.charging,
  });

  factory BatteryHistoryEntry.fromJson(Map<String, dynamic> json) {
    return BatteryHistoryEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      percent: json['percent'] as int? ?? 0,
      mv: json['mv'] as int? ?? 0,
      charging: json['charging'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 3: Run analysis**

Run: `flutter analyze`
Expected: No new issues

- [ ] **Step 4: Commit**

```bash
git add app/pubspec.yaml app/lib/features/devices/data/models/device_stats_model.dart
git commit -m "feat(app): add fl_chart dependency and battery history model"
```

---

## Task 6: Flutter — battery history chart and time remaining on device detail page

**Files:**
- Modify: `app/lib/features/devices/presentation/pages/device_detail_page.dart`

Add a small battery history chart card below the status card, and show estimated time remaining in the battery indicator.

- [ ] **Step 1: Add fl_chart import**

At the top of `device_detail_page.dart`, add:

```dart
import 'package:fl_chart/fl_chart.dart';
```

- [ ] **Step 2: Update _buildBatteryIndicator to show time remaining**

Replace the existing `_buildBatteryIndicator` method:

```dart
  Widget _buildBatteryIndicator(DeviceStats? stats, ColorScheme cs) {
    if (stats == null) return const SizedBox.shrink();
    final pct = stats.batteryPercent;
    if (pct == null) return const SizedBox.shrink();

    final isCharging = stats.batteryCharging == true || pct == 255;

    if (isCharging) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.battery_charging_full, size: 14, color: Colors.green),
        const SizedBox(width: 4),
        Text('Charging',
            style: TextStyle(fontSize: 12, color: Colors.green)),
      ]);
    }

    final icon = pct > 60
        ? Icons.battery_full
        : pct > 30
            ? Icons.battery_3_bar
            : Icons.battery_alert;
    final color = pct <= 20 ? Colors.red : cs.onSurfaceVariant;

    // Time remaining suffix
    final mins = stats.batteryMinutesRemaining;
    String label = '$pct%';
    if (mins != null && mins >= 0) {
      if (mins >= 60) {
        label += ' (~${mins ~/ 60}h ${mins % 60}m)';
      } else {
        label += ' (~${mins}m)';
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 12, color: color)),
    ]);
  }
```

- [ ] **Step 3: Add _buildBatteryChart widget method**

Add a new method in the `_StatusCardState` class (or as a standalone widget — place it as a method alongside `_buildBatteryIndicator`):

```dart
  Widget _buildBatteryChart(DeviceStats stats, ColorScheme cs) {
    final history = stats.batteryHistory
        .where((e) => !e.charging && e.percent <= 100)
        .toList();
    if (history.length < 2) return const SizedBox.shrink();

    // Build spots from history
    final earliest = history.first.timestamp;
    final spots = history.map((e) {
      final mins = e.timestamp.difference(earliest).inMinutes.toDouble();
      return FlSpot(mins, e.percent.toDouble());
    }).toList();

    final maxX = spots.last.x;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Battery',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  minX: 0,
                  maxX: maxX,
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                      strokeWidth: 0.5,
                    ),
                    drawVerticalLine: false,
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 25,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        interval: maxX > 120 ? 60 : 30,
                        getTitlesWidget: (value, meta) {
                          final h = (value / 60).floor();
                          return Text(
                            h > 0 ? '${h}h' : '${value.toInt()}m',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: spots.last.y <= 20
                          ? Colors.red
                          : spots.last.y <= 40
                              ? Colors.orange
                              : Colors.green,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: (spots.last.y <= 20
                                ? Colors.red
                                : spots.last.y <= 40
                                    ? Colors.orange
                                    : Colors.green)
                            .withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                  lineTouchData: const LineTouchData(enabled: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4: Insert the chart into the ListView**

Find where the status card is rendered in the ListView children (in the `_DeviceDetailBody` or equivalent widget) and add the chart card right after the status card:

```dart
// After the _StatusCard widget in the ListView children:
if (_stats != null && _stats!.batteryHistory.isNotEmpty)
  _buildBatteryChart(_stats!, cs),
```

Note: The `_buildBatteryChart` method and chart insertion need to be in the same stateful widget that has access to `_stats`. Since `_StatusCard` already has this state, the chart should be built inside the status card's build method or the chart method should be lifted to the parent. Check the actual widget tree and place accordingly — the chart must have access to the `_stats` variable.

- [ ] **Step 5: Run analysis**

Run: `flutter analyze`
Expected: No new issues

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/devices/presentation/pages/device_detail_page.dart
git commit -m "feat(app): battery history chart and time remaining on device detail"
```

---

## Task 7: Deep sleep with touch-to-wake on critical battery

**Files:**
- Modify: `firmware/include/power_manager.h`
- Modify: `firmware/src/power_manager.cpp`

Add an `enterDeepSleep()` function that configures GPIO17 (touch INT) as ext0 wakeup source and enters ESP32-S3 hardware deep sleep.

- [ ] **Step 1: Add enterDeepSleep declaration to power_manager.h**

Add after the existing function declarations:

```cpp
/// Enter ESP32-S3 hardware deep sleep.
/// Wakes on touch (GPIO17 ext0 LOW). This is a full reset on wake —
/// WiFi, FreeRTOS tasks, and all state are lost. Only use for critical battery.
void enterDeepSleep();
```

- [ ] **Step 2: Implement enterDeepSleep in power_manager.cpp**

Add at the end of the file before the closing namespace (requires adding `#include "config.h"` and `#include <esp_sleep.h>` at the top):

```cpp
#include "config.h"
#include <esp_sleep.h>
```

```cpp
void power_manager::enterDeepSleep() {
    Serial.println("[Power] Entering DEEP SLEEP — wake on touch (GPIO17)");
    Serial.flush();

    // Turn off display
    display::sleep();
    delay(300);  // let fade-out complete

    // Configure touch INT (GPIO17) as ext0 wake source — wakes on LOW
    esp_sleep_enable_ext0_wakeup(static_cast<gpio_num_t>(TOUCH_INT), 0);

    // Enter deep sleep — CPU resets on wake, setup() runs again
    esp_deep_sleep_start();
    // Never reaches here
}
```

- [ ] **Step 3: Build firmware**

Run: `pio run`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git add firmware/include/power_manager.h firmware/src/power_manager.cpp
git commit -m "feat(power): add enterDeepSleep with GPIO17 touch-to-wake"
```

---

## Task 8: Add critical_shutdown resilience audio clip

**Files:**
- Modify: `firmware/include/resilience_audio.h`
- Modify: `firmware/src/resilience_audio.cpp`

- [ ] **Step 1: Add CRITICAL_SHUTDOWN to the Clip enum**

In `resilience_audio.h`, add after `LOW_BATTERY`:

```cpp
    CRITICAL_SHUTDOWN, // "Going to sleep now, plug me in to wake up"
```

- [ ] **Step 2: Update resilience_audio.cpp**

Change `CLIP_COUNT` from 8 to 9:

```cpp
static const uint8_t CLIP_COUNT = 9;
```

Add the filename to `CLIP_FILES[]` after `"low_battery.opus"`:

```cpp
    "critical_shutdown.opus", // CRITICAL_SHUTDOWN
```

- [ ] **Step 3: Build firmware**

Run: `pio run`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git add firmware/include/resilience_audio.h firmware/src/resilience_audio.cpp
git commit -m "feat(resilience): add CRITICAL_SHUTDOWN audio clip slot"
```

---

## Task 9: Critical battery deep sleep trigger with goodnight TTS

**Files:**
- Modify: `firmware/src/main.cpp`

When battery is critical (≤10%) and not charging: if IDLE, play goodnight TTS then deep sleep. If not IDLE, wait for IDLE (up to 30s timeout) then silent deep sleep.

- [ ] **Step 1: Add deep sleep trigger logic to main loop**

In `main.cpp`, find the existing critical power saving block (the `criticalDimApplied` section). After that block, add:

```cpp
    // Deep sleep on critical battery — last resort power preservation
    {
        static bool deepSleepTriggered = false;
        static uint32_t deepSleepWaitStart = 0;

        if (battery::isCritical() && !battery::isCharging() && !deepSleepTriggered) {
            deepSleepTriggered = true;

            if (appState.botState == BotState::IDLE) {
                // IDLE — play goodnight clip then sleep
                Serial.println("[Battery] Critical + IDLE — goodnight then deep sleep");
                resilience_audio::playClip(resilience_audio::Clip::CRITICAL_SHUTDOWN);
                delay(500);  // let audio finish
                power_manager::enterDeepSleep();
            } else {
                // Not IDLE — wait for idle state (max 30s)
                Serial.println("[Battery] Critical + busy — waiting for IDLE to deep sleep");
                deepSleepWaitStart = millis();
            }
        }

        // Waiting for IDLE to deep sleep (timeout after 30s)
        if (deepSleepTriggered && deepSleepWaitStart > 0) {
            if (appState.botState == BotState::IDLE) {
                Serial.println("[Battery] Now IDLE — goodnight then deep sleep");
                resilience_audio::playClip(resilience_audio::Clip::CRITICAL_SHUTDOWN);
                delay(500);
                power_manager::enterDeepSleep();
            } else if (millis() - deepSleepWaitStart > 30000) {
                // Timeout — silent deep sleep to preserve battery
                Serial.println("[Battery] Critical timeout — silent deep sleep");
                power_manager::enterDeepSleep();
            }
        }

        // Reset if charging resumes
        if (battery::isCharging()) {
            deepSleepTriggered = false;
            deepSleepWaitStart = 0;
        }
    }
```

- [ ] **Step 2: Build firmware**

Run: `pio run`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add firmware/src/main.cpp
git commit -m "feat(battery): critical deep sleep with goodnight TTS and 30s idle wait"
```

---

## Task 10: Full integration build and verification

- [ ] **Step 1: Build firmware**

Run: `pio run`
Expected: SUCCESS

- [ ] **Step 2: Flutter analysis**

Run: `cd app && flutter analyze`
Expected: No new issues

- [ ] **Step 3: Backend type check**

Run: `cd backend && npx tsc --noEmit`
Expected: Only pre-existing spec file errors (devices.controller.spec.ts, proactive.service.spec.ts)

- [ ] **Step 4: Final commit with all changes**

If any uncommitted files remain:
```bash
git add -A
git commit -m "feat(battery): smart battery — display colors, history chart, discharge estimate, critical deep sleep"
```
