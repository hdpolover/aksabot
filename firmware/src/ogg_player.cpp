#include "ogg_player.h"
#include "sd_storage.h"
#include "opus_codec.h"
#include "audio_io.h"
#include "state.h"
#include "config.h"
#include <SD_MMC.h>
#define SD SD_MMC
#include <Arduino.h>
#include <esp_heap_caps.h>

// ── Streaming Ogg page reader ─────────────────────────────────────────────────
//
// Reads one Ogg page at a time from a File object — no whole-file heap alloc.
// An Ogg page is at most 65,536 bytes but in practice Opus pages are ~4 KB
// (enough for ~250ms of 16kbps audio). We read the 27-byte fixed header, then
// the segment table, then the page body.  Total heap for one page: ~8 KB max,
// allocated once from PSRAM so no fragmentation.
//
// SDIO 4-bit throughput on ESP32-S3: ~20 MB/s.  A 4 KB page reads in < 0.5ms,
// which is ~800× faster than the audio it contains (16 kbps ≈ 2 KB/s).
// No dropout risk.

static int16_t  s_pcm[OPUS_FRAME_SAMPLES];
static uint8_t  s_pktBuf[512];   // max Opus packet at 16 kbps
static uint8_t  s_segTable[255]; // Ogg segment table (up to 255 entries)
static uint8_t* s_pageBody = nullptr; // 64KB page body — allocated from PSRAM in init()

/// Decode and play all audio pages from an already-opened File.
/// Caller is responsible for open/close and guard checks.
static void streamDecode(File& f) {
    uint8_t header[27];
    int     pageNum = 0;
    size_t  pktLen  = 0;

    while (true) {
        // Stop if TTS takes over the speaker
        if (appState.botState == BotState::SPEAKING) return;

        // Read fixed 27-byte Ogg page header
        if (f.read(header, 27) != 27) break;

        // Validate OggS capture pattern
        if (memcmp(header, "OggS", 4) != 0) break;

        uint8_t numSegs = header[26];

        // Read segment table
        if (f.read(s_segTable, numSegs) != numSegs) break;

        // Calculate page body size
        size_t bodySize = 0;
        for (uint8_t i = 0; i < numSegs; i++) bodySize += s_segTable[i];

        if (bodySize > sizeof(s_pageBody)) {
            // Oversized page — skip it by seeking forward
            f.seek(f.position() + bodySize);
            pageNum++;
            continue;
        }

        // Read page body
        if (bodySize > 0 && f.read(s_pageBody, bodySize) != bodySize) break;

        // Skip OpusHead (page 0) and OpusTags (page 1) — metadata only
        if (pageNum >= 2) {
            size_t dataPos = 0;
            for (uint8_t i = 0; i < numSegs; i++) {
                if (appState.botState == BotState::SPEAKING) return;

                uint8_t segSize = s_segTable[i];

                if (pktLen + segSize <= sizeof(s_pktBuf)) {
                    memcpy(s_pktBuf + pktLen, s_pageBody + dataPos, segSize);
                    pktLen += segSize;
                } else {
                    pktLen = 0;  // overflow — drop and reset
                }
                dataPos += segSize;

                if (segSize < 255) {
                    // End of Opus packet (segment < 255 is the terminator)
                    if (pktLen > 0) {
                        int samples = opus_codec::decode(s_pktBuf, pktLen, s_pcm, OPUS_FRAME_SAMPLES);
                        if (samples > 0) audio_io::writeSpeaker(s_pcm, samples);
                    }
                    pktLen = 0;
                }
                // segSize == 255: packet spans next segment (keep accumulating)
            }
        }

        pageNum++;
    }
}

// ── Public API ────────────────────────────────────────────

void ogg_player::init() {
    if (!s_pageBody) {
        s_pageBody = (uint8_t*)heap_caps_malloc(65536, MALLOC_CAP_SPIRAM);
        if (s_pageBody) {
            Serial.println("[OggPlayer] Page buffer allocated (64 KB PSRAM)");
        } else {
            Serial.println("[OggPlayer] PSRAM alloc failed — Ogg playback disabled");
        }
    }
}

bool ogg_player::playFile(const char* path) {
    if (!s_pageBody) return false;
    if (appState.botState == BotState::SPEAKING)  return false;
    if (appState.botState == BotState::LISTENING) return false;
    if (!sd_storage::isMounted()) return false;

    if (!SD.exists(path)) {
        Serial.printf("[OggPlayer] Missing: %s\n", path);
        return false;
    }

    File f = SD.open(path, FILE_READ);
    if (!f) return false;

    streamDecode(f);
    f.close();
    return true;
}

void ogg_player::playData(const uint8_t* data, size_t dataLen) {
    // PSRAM-preloaded path — no file I/O. Only block SPEAKING (resilience clips
    // may fire during THINKING, e.g. playClip(OFFLINE) when Wi-Fi drops).
    if (!s_pageBody) return;
    if (appState.botState == BotState::SPEAKING) return;

    size_t pos     = 0;
    int    pageNum = 0;
    size_t pktLen  = 0;

    while (pos + 27 <= dataLen) {
        if (appState.botState == BotState::SPEAKING) return;

        if (memcmp(data + pos, "OggS", 4) != 0) break;

        uint8_t numSegs      = data[pos + 26];
        size_t  segTableBase = pos + 27;
        if (segTableBase + numSegs > dataLen) break;

        size_t pageDataSize = 0;
        for (uint8_t i = 0; i < numSegs; i++) pageDataSize += data[segTableBase + i];

        size_t pageDataBase = segTableBase + numSegs;
        if (pageDataBase + pageDataSize > dataLen) break;

        if (pageNum >= 2) {
            const uint8_t* segTable = data + segTableBase;
            const uint8_t* pageData = data + pageDataBase;
            size_t          dataPos = 0;

            for (uint8_t i = 0; i < numSegs; i++) {
                if (appState.botState == BotState::SPEAKING) return;

                uint8_t segSize = segTable[i];

                if (pktLen + sizeof(s_pktBuf) > 0 && pktLen + segSize <= sizeof(s_pktBuf)) {
                    memcpy(s_pktBuf + pktLen, pageData + dataPos, segSize);
                    pktLen += segSize;
                } else {
                    pktLen = 0;
                }
                dataPos += segSize;

                if (segSize < 255) {
                    if (pktLen > 0) {
                        int samples = opus_codec::decode(s_pktBuf, pktLen, s_pcm, OPUS_FRAME_SAMPLES);
                        if (samples > 0) audio_io::writeSpeaker(s_pcm, samples);
                    }
                    pktLen = 0;
                }
            }
        }

        pos = pageDataBase + pageDataSize;
        pageNum++;
    }
}
