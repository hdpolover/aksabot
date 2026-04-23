#include <Arduino.h>
#include "camera.h"

void setup() {
    Serial.begin(115200);
    delay(1000);
    if (camera::init()) {
        Serial.println("[BOOT] Camera OK");
    } else {
        Serial.println("[BOOT] Camera FAIL");
    }
}
void loop() {}
