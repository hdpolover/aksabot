#pragma once
#include <stddef.h>
#include <stdint.h>

/// Shared Ogg Opus player — used by ui_audio, emotion_audio, sfx_audio,
/// and resilience_audio. Keeps the Ogg page parser in one place.
namespace ogg_player {

/// Open an Ogg Opus file from SD, decode all audio pages, and write to speaker.
/// Handles file open → malloc → decode → free internally.
/// Returns false if SD not mounted, file missing, alloc failed, or bot is SPEAKING/LISTENING.
bool playFile(const char* path, size_t maxBytes = 64 * 1024);

/// Decode and play an Ogg Opus buffer already loaded in memory.
/// Used by resilience_audio which preloads clips into PSRAM.
/// Guards only against SPEAKING (resilience clips may play during THINKING).
void playData(const uint8_t* data, size_t len);

}  // namespace ogg_player
