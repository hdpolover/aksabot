#include "motion.h"
#include <Arduino.h>
#include <stdlib.h>

static int    _threshold = 15;
static bool   _enabled   = true;
static bool   _detected  = false;
static int    _lastScore = 0;
static size_t _prevSize  = 0;

namespace motion {

void init(int threshold) {
    _threshold = threshold;
    _enabled   = true;
    _detected  = false;
    _prevSize  = 0;
}

void setThreshold(int t) { _threshold = t; }
void setEnabled(bool e)  { _enabled = e; if (!e) _detected = false; }
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
