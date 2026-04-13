#include "emotion_audio.h"
#include "ogg_player.h"
#include <Arduino.h>

static const char* EMOTION_DIR = "/audio/emotion";

void emotion_audio::play(const char* expression) {
    if (!expression || !*expression) return;

    char path[72];
    snprintf(path, sizeof(path), "%s/%s.opus", EMOTION_DIR, expression);

    if (!ogg_player::playFile(path)) {
        Serial.printf("[EmotionAudio] Could not play: %s\n", path);
    }
}
