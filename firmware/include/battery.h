#pragma once
#include <cstdint>

namespace battery {

static constexpr uint8_t LOW_THRESHOLD      = 20;
static constexpr uint8_t CRITICAL_THRESHOLD = 10;

void     init();
uint8_t  readPercent();   // returns 255 if USB powered
bool     isUsbPowered();
bool     isLow();         // last reading ≤ LOW_THRESHOLD and not USB
bool     isCritical();    // last reading ≤ CRITICAL_THRESHOLD and not USB
uint16_t lastVoltageMillivolts();

}  // namespace battery
