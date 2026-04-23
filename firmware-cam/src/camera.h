#pragma once
#include "esp_camera.h"

namespace camera {
    bool init();
    bool setResolution(int framesize);
    camera_fb_t* capture();
    void returnFrame(camera_fb_t* fb);
}
