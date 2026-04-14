#pragma once
#include <cstdint>

// Bot state machine — mirrors backend session states
enum class BotState {
    IDLE,       // Default, waiting for interaction
    LISTENING,  // Touch held, recording audio
    THINKING,   // Waiting for backend response
    SPEAKING,   // Playing audio response from AI
    INTERCOM,   // Playing voice message pushed from mobile app
    OFFLINE,    // No backend connection
    SLEEPING,   // Power saving
};

// BLE presence detection states
enum class PresenceState {
    UNKNOWN,    // Not yet determined (startup)
    PRESENT,    // Phone detected at desk
    LEAVING,    // Signal weakening, grace period active
    AWAY,       // Phone not detected, bot should sleep
};

/// How the current LISTENING session was triggered.
enum class ListenTrigger : uint8_t {
    TOUCH,            // Push-to-talk (touch hold)
    WAKE_WORD,        // "Hey Aksa" wake word detection
    GESTURE,          // APDS-9960 hand wave
    INTERCOM_REPLY,   // Walkie-talkie reply during active intercom session
};

// Global state (accessed from multiple FreeRTOS tasks)
struct AppState {
    volatile BotState botState = BotState::OFFLINE;
    volatile PresenceState presenceState = PresenceState::UNKNOWN;
    volatile bool wifiConnected = false;
    volatile bool wsConnected = false;
    volatile bool touchActive = false;
    volatile bool interrupted = false;
    volatile ListenTrigger listenTrigger = ListenTrigger::TOUCH;
};

extern AppState appState;
