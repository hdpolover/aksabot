#include "resilience_audio.h"
#include "ogg_player.h"
#include "sd_storage.h"
#include "state.h"
#include <SD_MMC.h>
#define SD SD_MMC
#include <Arduino.h>

static const char* AUDIO_DIR = "/audio/resilience";

// ── Clip metadata ──────────────────────────────────────

struct ClipData {
    uint8_t* data;
    size_t len;
    bool loaded;
};

static const uint8_t CLIP_COUNT = 9;
static ClipData clips[CLIP_COUNT] = {};

// Map Clip enum to filename
static const char* CLIP_FILES[] = {
    "offline.opus",     // OFFLINE
    "error.opus",       // ERROR
    "stt_fail.opus",    // STT_FAIL
    "boot.opus",        // BOOT
    "thinking.opus",    // THINKING
    "sleep.opus",       // SLEEP
    "wake.opus",        // WAKE
    "low_battery.opus",        // LOW_BATTERY
    "critical_shutdown.opus",  // CRITICAL_SHUTDOWN
};

static uint8_t clipIndex(resilience_audio::Clip clip) {
    return static_cast<uint8_t>(clip);
}

// ── Public API ─────────────────────────────────────────

uint8_t resilience_audio::init() {
    if (!sd_storage::isMounted()) {
        Serial.println("[Resilience] SD not mounted — no fallback audio");
        return 0;
    }

    uint8_t loaded = 0;

    for (uint8_t i = 0; i < CLIP_COUNT; i++) {
        char path[64];
        snprintf(path, sizeof(path), "%s/%s", AUDIO_DIR, CLIP_FILES[i]);

        if (!SD.exists(path)) continue;

        File f = SD.open(path, FILE_READ);
        if (!f) continue;

        size_t fileSize = f.size();
        if (fileSize == 0 || fileSize > 64 * 1024) {
            // Skip files over 64KB — resilience clips should be short
            f.close();
            continue;
        }

        uint8_t* buf = (uint8_t*)ps_malloc(fileSize);
        if (!buf) {
            Serial.printf("[Resilience] PSRAM alloc failed for %s (%u bytes)\n",
                CLIP_FILES[i], (uint32_t)fileSize);
            f.close();
            continue;
        }

        f.read(buf, fileSize);
        f.close();

        clips[i].data = buf;
        clips[i].len = fileSize;
        clips[i].loaded = true;
        loaded++;

        Serial.printf("[Resilience] Loaded %s (%u bytes)\n",
            CLIP_FILES[i], (uint32_t)fileSize);
    }

    Serial.printf("[Resilience] %u/%u clips loaded\n", loaded, CLIP_COUNT);
    return loaded;
}

bool resilience_audio::hasClip(Clip clip) {
    uint8_t idx = clipIndex(clip);
    if (idx >= CLIP_COUNT) return false;
    return clips[idx].loaded;
}

bool resilience_audio::getClip(Clip clip, const uint8_t** data, size_t* len) {
    uint8_t idx = clipIndex(clip);
    if (idx >= CLIP_COUNT || !clips[idx].loaded) return false;

    *data = clips[idx].data;
    *len = clips[idx].len;
    return true;
}

const char* resilience_audio::clipFileName(Clip clip) {
    uint8_t idx = clipIndex(clip);
    if (idx >= CLIP_COUNT) return "unknown";
    return CLIP_FILES[idx];
}

void resilience_audio::playClip(Clip clip) {
    const uint8_t* data;
    size_t len;
    if (!getClip(clip, &data, &len)) {
        Serial.printf("[Resilience] Clip not loaded: %s\n", clipFileName(clip));
        return;
    }
    // ogg_player::playData guards against SPEAKING internally.
    // Resilience clips may fire during THINKING (e.g. offline, stt_fail).
    ogg_player::playData(data, len);
}
