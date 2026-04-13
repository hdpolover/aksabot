#include "ui_audio.h"
#include "ogg_player.h"
#include "state.h"
#include <Arduino.h>

static const char* UI_AUDIO_DIR = "/audio/ui";

static const char* clipFileName(ui_audio::Clip clip) {
    switch (clip) {
        case ui_audio::Clip::TAP:                  return "tap.opus";
        case ui_audio::Clip::HOLD_START:           return "hold_start.opus";
        case ui_audio::Clip::RECORDING_STOP:       return "recording_stop.opus";
        case ui_audio::Clip::WIFI_CONNECTED:       return "wifi_connected.opus";
        case ui_audio::Clip::SERVER_CONNECTED:     return "server_connected.opus";
        case ui_audio::Clip::SERVER_DISCONNECTED:  return "server_disconnected.opus";
        case ui_audio::Clip::NOTIFICATION:         return "notification.opus";
        case ui_audio::Clip::PRESENCE_ARRIVED:     return "presence_arrived.opus";
        case ui_audio::Clip::PRESENCE_DEPARTED:    return "presence_departed.opus";
        default: return nullptr;
    }
}

void ui_audio::play(Clip clip) {
    const char* fname = clipFileName(clip);
    if (!fname) return;

    char path[72];
    snprintf(path, sizeof(path), "%s/%s", UI_AUDIO_DIR, fname);
    ogg_player::playFile(path, 32 * 1024);
}
