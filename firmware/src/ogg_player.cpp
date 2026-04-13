#include "ogg_player.h"
#include "sd_storage.h"
#include "opus_codec.h"
#include "audio_io.h"
#include "state.h"
#include "config.h"
#include <SD_MMC.h>
#define SD SD_MMC
#include <Arduino.h>

/// Core Ogg page parser. Shared by playFile() and playData().
/// Skips first two Ogg pages (OpusHead + OpusTags), then decodes audio packets.
/// Stops early if botState becomes SPEAKING (TTS kicked in mid-playback).
static void decodeAndPlay(const uint8_t* data, size_t dataLen) {
    // Static buffers — safe because all callers run on Core 1 serially.
    static int16_t  pcm[OPUS_FRAME_SAMPLES];
    static uint8_t  pktBuf[512];  // max Opus packet; 512B is safe at 16 kbps

    size_t pos     = 0;
    int    pageNum = 0;
    size_t pktLen  = 0;  // bytes accumulated for current cross-segment packet

    while (pos + 27 <= dataLen) {
        // Validate OggS capture pattern
        if (memcmp(data + pos, "OggS", 4) != 0) break;

        uint8_t numSegs      = data[pos + 26];
        size_t  segTableBase = pos + 27;
        if (segTableBase + numSegs > dataLen) break;

        size_t pageDataSize = 0;
        for (uint8_t i = 0; i < numSegs; i++) pageDataSize += data[segTableBase + i];

        size_t pageDataBase = segTableBase + numSegs;
        if (pageDataBase + pageDataSize > dataLen) break;

        if (pageNum >= 2) {
            // Audio page — extract Opus packets from segment table
            const uint8_t* segTable = data + segTableBase;
            const uint8_t* pageData = data + pageDataBase;
            size_t          dataPos = 0;

            for (uint8_t i = 0; i < numSegs; i++) {
                // Stop early if TTS takes over the speaker
                if (appState.botState == BotState::SPEAKING) return;

                uint8_t segSize = segTable[i];

                if (pktLen + segSize <= sizeof(pktBuf)) {
                    memcpy(pktBuf + pktLen, pageData + dataPos, segSize);
                    pktLen += segSize;
                } else {
                    pktLen = 0;  // overflow — drop packet, reset
                }
                dataPos += segSize;

                if (segSize < 255) {
                    // segment < 255 marks end of Opus packet
                    if (pktLen > 0) {
                        int samples = opus_codec::decode(pktBuf, pktLen, pcm, OPUS_FRAME_SAMPLES);
                        if (samples > 0) audio_io::writeSpeaker(pcm, samples);
                    }
                    pktLen = 0;
                }
                // segSize == 255: packet continues in next segment/page
            }
        }

        pos = pageDataBase + pageDataSize;
        pageNum++;
    }
}

// ── Public API ────────────────────────────────────────────

bool ogg_player::playFile(const char* path, size_t maxBytes) {
    if (appState.botState == BotState::SPEAKING)  return false;
    if (appState.botState == BotState::LISTENING) return false;
    if (!sd_storage::isMounted()) return false;

    if (!SD.exists(path)) {
        Serial.printf("[OggPlayer] Missing: %s\n", path);
        return false;
    }

    File f = SD.open(path, FILE_READ);
    if (!f) return false;

    size_t fileSize = f.size();
    if (fileSize == 0 || fileSize > maxBytes) {
        f.close();
        return false;
    }

    uint8_t* buf = (uint8_t*)malloc(fileSize);
    if (!buf) {
        Serial.printf("[OggPlayer] malloc failed for %s (%u bytes)\n", path, (unsigned)fileSize);
        f.close();
        return false;
    }

    f.read(buf, fileSize);
    f.close();

    decodeAndPlay(buf, fileSize);
    free(buf);
    return true;
}

void ogg_player::playData(const uint8_t* data, size_t len) {
    // PSRAM-preloaded path — no file I/O. Only block SPEAKING (resilience clips
    // may fire during THINKING, e.g. playClip(OFFLINE) when Wi-Fi drops).
    if (appState.botState == BotState::SPEAKING) return;
    decodeAndPlay(data, len);
}
