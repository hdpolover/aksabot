#pragma once
#include <cstdint>
#include <cstddef>

/// Recording buffer for network resilience.
///
/// When the WebSocket disconnects mid-recording, Opus frames are
/// buffered to SD card. On reconnection, buffered frames are resent
/// to the backend to avoid losing the user's speech.
///
/// Files: /audio/buffer/pending_<timestamp>.opus
namespace recording_buffer {

/// Initialize the recording buffer. Call after SD init.
void init();

/// Check if there are any pending buffered recordings.
bool hasPending();

/// Start buffering to SD instead of WebSocket.
/// Returns true if buffer file was created successfully.
bool startBuffering();

/// Write an Opus frame to the active buffer file.
bool writeFrame(const uint8_t* data, size_t len);

/// Stop buffering and close the active file.
void stopBuffering();

/// Returns true if currently buffering to SD.
bool isBuffering();

/// Resend all pending buffer files over WebSocket.
/// Should be called after WS reconnects and session is re-established.
/// Sends each frame as a binary WS message, then deletes the file.
/// Returns the number of files successfully resent.
uint8_t resendPending();

/// Delete all pending buffer files without resending.
void discardPending();

/// Get the number of pending buffer files.
uint8_t getPendingCount();

}  // namespace recording_buffer
