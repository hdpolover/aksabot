#include "ui_audio.h"
#include "sd_storage.h"
#include "opus_codec.h"
#include "audio_io.h"
#include "state.h"
#include "config.h"
#include <SD_MMC.h>
#define SD SD_MMC
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

/// Parse and play an Ogg Opus file from an in-memory buffer.
///
/// Ogg format: each page starts with "OggS" + 26 bytes of header, then
/// a segment table, then the page data. The first two pages are always
/// the OpusHead and OpusTags headers — we skip them. Subsequent pages
/// contain Opus audio packets delimited by segment boundaries (a segment
/// of length < 255 ends a packet; length == 255 continues it).
///
/// Stops early if BotState becomes SPEAKING (TTS kicked in).
static void playOggOpus(const uint8_t* data, size_t dataLen) {
    // Static so we don't blow the stack — only called from Core 1 serially.
    static int16_t  pcm[OPUS_FRAME_SAMPLES];
    static uint8_t  pktBuf[512];  // max single Opus packet (~40B at 16kbps; 512 is safe)

    size_t pos      = 0;
    int    pageNum  = 0;
    size_t pktLen   = 0;  // accumulated bytes for the current cross-page packet

    while (pos + 27 <= dataLen) {
        // Validate OggS capture pattern
        if (memcmp(data + pos, "OggS", 4) != 0) {
            Serial.printf("[UIAudio] Bad OggS at pos %u — stopping\n", (unsigned)pos);
            break;
        }

        uint8_t numSegs       = data[pos + 26];
        size_t  segTableBase  = pos + 27;
        if (segTableBase + numSegs > dataLen) break;

        size_t pageDataSize = 0;
        for (uint8_t i = 0; i < numSegs; i++) pageDataSize += data[segTableBase + i];

        size_t pageDataBase = segTableBase + numSegs;
        if (pageDataBase + pageDataSize > dataLen) break;

        if (pageNum >= 2) {
            // Audio page — extract Opus packets
            const uint8_t* segTable = data + segTableBase;
            const uint8_t* pageData = data + pageDataBase;
            size_t          dataPos = 0;

            for (uint8_t i = 0; i < numSegs; i++) {
                uint8_t segSize = segTable[i];

                // Stop early if TTS starts during playback
                if (appState.botState == BotState::SPEAKING) return;

                // Accumulate segment into packet buffer (overflow-safe)
                if (pktLen + segSize <= sizeof(pktBuf)) {
                    memcpy(pktBuf + pktLen, pageData + dataPos, segSize);
                    pktLen += segSize;
                } else {
                    // Packet larger than buffer — skip it and reset
                    pktLen = 0;
                }
                dataPos += segSize;

                if (segSize < 255) {
                    // Segment length < 255 marks the end of a packet
                    if (pktLen > 0) {
                        int samples = opus_codec::decode(pktBuf, pktLen, pcm, OPUS_FRAME_SAMPLES);
                        if (samples > 0) audio_io::writeSpeaker(pcm, samples);
                    }
                    pktLen = 0;
                }
                // segSize == 255 means the packet continues in the next segment/page
            }
        }

        pos = pageDataBase + pageDataSize;
        pageNum++;
    }
}

void ui_audio::play(Clip clip) {
    if (appState.botState == BotState::SPEAKING)  return;  // TTS active
    if (appState.botState == BotState::LISTENING) return;  // mic is open
    if (!sd_storage::isMounted()) return;

    const char* fname = clipFileName(clip);
    if (!fname) return;

    char path[64];
    snprintf(path, sizeof(path), "%s/%s", UI_AUDIO_DIR, fname);

    if (!SD.exists(path)) {
        Serial.printf("[UIAudio] Missing: %s\n", path);
        return;
    }

    File f = SD.open(path, FILE_READ);
    if (!f) return;

    size_t fileSize = f.size();
    if (fileSize == 0 || fileSize > 32 * 1024) {
        f.close();
        return;
    }

    uint8_t* buf = (uint8_t*)malloc(fileSize);
    if (!buf) {
        Serial.printf("[UIAudio] malloc failed (%u bytes)\n", (unsigned)fileSize);
        f.close();
        return;
    }

    f.read(buf, fileSize);
    f.close();

    playOggOpus(buf, fileSize);
    free(buf);
}
