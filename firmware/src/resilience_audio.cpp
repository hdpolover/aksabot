#include "resilience_audio.h"
#include "sd_storage.h"
#include "opus_codec.h"
#include "audio_io.h"
#include "state.h"
#include "config.h"
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

static const uint8_t CLIP_COUNT = 7;
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
    if (appState.botState == BotState::SPEAKING)  return;
    if (appState.botState == BotState::LISTENING) return;

    const uint8_t* data;
    size_t len;
    if (!getClip(clip, &data, &len)) {
        Serial.printf("[Resilience] Clip not loaded: %s\n", clipFileName(clip));
        return;
    }

    // Parse Ogg Opus container and play each audio packet.
    // The files on SD are standard Ogg Opus (ffmpeg output) — we need to
    // skip the two header pages and extract raw Opus packets from the rest.
    static int16_t pcm[OPUS_FRAME_SAMPLES];
    static uint8_t pktBuf[512];

    size_t pos     = 0;
    int    pageNum = 0;
    size_t pktLen  = 0;

    while (pos + 27 <= len) {
        if (memcmp(data + pos, "OggS", 4) != 0) break;

        uint8_t numSegs      = data[pos + 26];
        size_t  segTableBase = pos + 27;
        if (segTableBase + numSegs > len) break;

        size_t pageDataSize = 0;
        for (uint8_t i = 0; i < numSegs; i++) pageDataSize += data[segTableBase + i];

        size_t pageDataBase = segTableBase + numSegs;
        if (pageDataBase + pageDataSize > len) break;

        if (pageNum >= 2) {
            const uint8_t* segTable = data + segTableBase;
            const uint8_t* pageData = data + pageDataBase;
            size_t          dataPos = 0;

            for (uint8_t i = 0; i < numSegs; i++) {
                if (appState.botState == BotState::SPEAKING) return;

                uint8_t segSize = segTable[i];
                if (pktLen + segSize <= sizeof(pktBuf)) {
                    memcpy(pktBuf + pktLen, pageData + dataPos, segSize);
                    pktLen += segSize;
                } else {
                    pktLen = 0;  // overflow — drop packet
                }
                dataPos += segSize;

                if (segSize < 255) {
                    if (pktLen > 0) {
                        int samples = opus_codec::decode(pktBuf, pktLen, pcm, OPUS_FRAME_SAMPLES);
                        if (samples > 0) audio_io::writeSpeaker(pcm, samples);
                    }
                    pktLen = 0;
                }
            }
        }

        pos = pageDataBase + pageDataSize;
        pageNum++;
    }
}
