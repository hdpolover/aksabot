#pragma once
#include <stddef.h>

namespace metrics {
    void onFrame(size_t frameBytes);
    void tick(bool motionDetected);
    int fps();
    int frameMs();
}
