#pragma once
#include <cstdint>
#include <cstddef>

/// Pre-loaded fallback audio for offline/error scenarios.
///
/// These are short Opus-encoded audio clips stored on SD card under
/// /audio/resilience/. They're loaded into PSRAM on startup for
/// instant playback without SD access.
///
/// Usage: when the backend is unreachable, STT fails, or an error
/// occurs, play the appropriate resilience audio instead of silence.
namespace resilience_audio {

/// Audio clip identifiers.
enum class Clip {
    OFFLINE,        // "I'm offline right now"
    ERROR,          // "Something went wrong"
    STT_FAIL,       // "I didn't catch that"
    BOOT,           // Startup chime
    THINKING,       // Ambient thinking sound
    SLEEP,          // Going to sleep sound
    WAKE,           // Waking up sound
};

/// Load all resilience audio from SD into PSRAM.
/// Files expected at /audio/resilience/<name>.opus
/// Returns the number of clips successfully loaded.
uint8_t init();

/// Check if a specific clip is available.
bool hasClip(Clip clip);

/// Get the Opus data and length for a clip.
/// Returns false if clip is not loaded.
bool getClip(Clip clip, const uint8_t** data, size_t* len);

/// Get the file name for a clip (without path).
const char* clipFileName(Clip clip);

}  // namespace resilience_audio
