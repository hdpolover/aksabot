#include "motion.h"
#include <Arduino.h>
#include <stdlib.h>

static volatile int    _threshold = 15;
static volatile bool   _enabled   = true;
static volatile bool   _detected  = false;
static volatile int    _lastScore = 0;
static          size_t _prevSize  = 0;  // Core 0 only

namespace motion {

void init(int threshold) {
    _threshold = threshold;
    _enabled   = true;
    _detected  = false;
    _lastScore = 0;
    _prevSize  = 0;
}

void setThreshold(int t) { _threshold = t; }
void setEnabled(bool e)  { _enabled = e; if (!e) { _detected = false; _lastScore = 0; } }
bool isEnabled()         { return _enabled; }
bool detected()          { return _detected; }
int  lastScore()         { return _lastScore; }

void checkSize(size_t frameBytes) {
    if (!_enabled || _prevSize == 0) {
        _prevSize = frameBytes;
        return;
    }
    int diff  = abs((int)frameBytes - (int)_prevSize);
    _lastScore = (int)((diff * 100UL) / _prevSize);
    bool prev  = _detected;
    _detected  = (_lastScore > _threshold);
    if (_detected && !prev) {
        Serial.printf("[MOTION] score=%d threshold=%d\n", _lastScore, _threshold);
    }
    _prevSize = frameBytes;
}

} // namespace motion
