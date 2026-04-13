#pragma once

/// SFX audio clips — comedic and personality sounds triggered by the LLM
/// via audio:sfx WebSocket events.
///
/// The LLM embeds [sfx:clipname] tags in its response text. The backend
/// strips these and sends audio:sfx {"clip":"clipname"} before the TTS
/// frames for that sentence, so the sound effect plays just before speech.
///
/// Clips are Ogg Opus files in /audio/sfx/ on the SD card.
namespace sfx_audio {

/// Play an SFX clip by name (without the .opus extension).
/// e.g. sfx_audio::play("rimshot") opens /audio/sfx/rimshot.opus
/// Silently skips if the file is missing, SD is not mounted, or bot is
/// SPEAKING / LISTENING.
void play(const char* clipName);

}  // namespace sfx_audio
