#include "sfx_audio.h"
#include "ogg_player.h"
#include <Arduino.h>

static const char* SFX_DIR = "/audio/sfx";

void sfx_audio::play(const char* clipName) {
    if (!clipName || !*clipName) return;

    char path[72];
    snprintf(path, sizeof(path), "%s/%s.opus", SFX_DIR, clipName);

    if (!ogg_player::playFile(path, 128 * 1024)) {
        Serial.printf("[SfxAudio] Could not play: %s\n", path);
    }
}
