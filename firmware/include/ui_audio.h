#pragma once

/// UI audio clips — short feedback sounds played on demand from SD card.
///
/// Clips are Ogg Opus files in /audio/ui/ on the SD card. They're opened,
/// decoded, and played at call time — no PSRAM preloading needed since
/// they're all under 1 second.
///
/// Safe to call from Core 1 (main loop, touch handler, WS event handler).
/// Silently skips if TTS is active, mic is open, SD is unmounted, or file
/// is missing.
namespace ui_audio {

enum class Clip {
    TAP,                 // Touch tap feedback (every tap)
    HOLD_START,          // Push-to-talk begins (mic opening)
    RECORDING_STOP,      // Recording sent to backend
    WIFI_CONNECTED,      // Wi-Fi handshake succeeded (reconnect)
    SERVER_CONNECTED,    // WebSocket connected to backend
    SERVER_DISCONNECTED, // WebSocket dropped
    NOTIFICATION,        // Reminder / proactive event
    PRESENCE_ARRIVED,    // User detected at desk
    PRESENCE_DEPARTED,   // User left desk
};

/// Play a UI clip. Blocks for the clip duration (<1s).
/// Skips silently if BotState is SPEAKING or LISTENING, SD is not mounted,
/// or the clip file is missing.
void play(Clip clip);

}  // namespace ui_audio
