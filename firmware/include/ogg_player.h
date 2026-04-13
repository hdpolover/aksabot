#pragma once
#include <stddef.h>
#include <stdint.h>

/// Shared Ogg Opus player — used by ui_audio, emotion_audio, sfx_audio,
/// and resilience_audio. Keeps the Ogg page parser in one place.
namespace ogg_player {

/// Open an Ogg Opus file from SD and stream it page-by-page, decoding audio
/// without loading the whole file into heap. No size cap — works for ambient
/// loops, long clips, and music tracks. Returns false if SD not mounted,
/// file missing, or bot is SPEAKING/LISTENING.
bool playFile(const char* path);

/// Decode and play an Ogg Opus buffer already loaded in memory.
/// Used by resilience_audio which preloads clips into PSRAM.
/// Guards only against SPEAKING (resilience clips may play during THINKING).
void playData(const uint8_t* data, size_t len);

}  // namespace ogg_player
