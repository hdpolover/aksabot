#pragma once
#include <cstdint>

namespace battery {

static constexpr uint8_t LOW_THRESHOLD      = 20;
static constexpr uint8_t CRITICAL_THRESHOLD = 10;

void     init();
uint8_t  readPercent();   // returns 255 if USB powered or charging
bool     isUsbPowered();  // voltage above USB threshold
bool     isCharging();    // USB powered OR voltage trending upward
bool     isLow();         // last reading ≤ LOW_THRESHOLD and not charging
bool     isCritical();    // last reading ≤ CRITICAL_THRESHOLD and not charging
uint16_t lastVoltageMillivolts();

/// Estimated minutes of battery remaining based on discharge rate.
/// Returns -1 if charging, unknown, or insufficient data.
int16_t minutesRemaining();

}  // namespace battery
