#pragma once
#include <stddef.h>

namespace motion {
    void init(int threshold = 15);
    void setThreshold(int t);
    void setEnabled(bool e);
    bool isEnabled();
    void checkSize(size_t frameBytes);
    bool detected();
    int  lastScore();
}
