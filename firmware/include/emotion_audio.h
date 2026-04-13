#pragma once

/// Emotion audio clips — short sound clips that match face expressions.
/// Triggered by face:expression WS events that include withSound:true.
/// Clips are Ogg Opus files in /audio/emotion/ on the SD card.
///
/// During the LLM pipeline, face:expression carries withSound:false (TTS follows
/// immediately). For standalone triggers (presence arrived/departed, proactive
/// events), withSound:true plays the matching clip.
namespace emotion_audio {

/// Play the audio clip associated with a face expression name.
/// Expression names match the face:expression WS payload (e.g. "happy", "sad").
/// Silently skips if the clip file is missing, SD is not mounted, or bot is
/// SPEAKING / LISTENING.
void play(const char* expression);

}  // namespace emotion_audio
