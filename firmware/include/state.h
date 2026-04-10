#pragma once

// Bot state machine — mirrors backend session states
enum class BotState {
    IDLE,       // Default, waiting for interaction
    LISTENING,  // Touch held, recording audio
    THINKING,   // Waiting for backend response
    SPEAKING,   // Playing audio response
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

// Global state (accessed from multiple FreeRTOS tasks)
struct AppState {
    volatile BotState botState = BotState::OFFLINE;
    volatile PresenceState presenceState = PresenceState::UNKNOWN;
    volatile bool wifiConnected = false;
    volatile bool wsConnected = false;
    volatile bool touchActive = false;
    volatile bool interrupted = false;
};

extern AppState appState;
