#include "recording_buffer.h"
#include "sd_storage.h"
#include "ws_client.h"
#include <SD.h>
#include <Arduino.h>

static const char* BUFFER_DIR = "/audio/buffer";
static const uint8_t MAX_PENDING = 8;

static File activeFile;
static bool buffering = false;
static bool initialized = false;

// ── Helpers ────────────────────────────────────────────

static void buildPath(char* buf, size_t bufLen, uint32_t timestamp) {
    snprintf(buf, bufLen, "%s/pending_%010u.opus", BUFFER_DIR, timestamp);
}

// ── Public API ─────────────────────────────────────────

void recording_buffer::init() {
    if (initialized) return;
    initialized = true;

    uint8_t count = getPendingCount();
    if (count > 0) {
        Serial.printf("[RecBuf] %u pending buffer file(s) from previous session\n", count);
    }
}

bool recording_buffer::hasPending() {
    if (!sd_storage::isMounted()) return false;

    File dir = SD.open(BUFFER_DIR);
    if (!dir || !dir.isDirectory()) return false;

    File entry = dir.openNextFile();
    bool found = (entry && !entry.isDirectory());
    if (entry) entry.close();
    dir.close();
    return found;
}

bool recording_buffer::startBuffering() {
    if (!sd_storage::isMounted()) return false;
    if (buffering) return true;

    char path[64];
    buildPath(path, sizeof(path), millis());

    activeFile = SD.open(path, FILE_WRITE);
    if (!activeFile) {
        Serial.printf("[RecBuf] Failed to create buffer: %s\n", path);
        return false;
    }

    buffering = true;
    Serial.printf("[RecBuf] Buffering to %s\n", path);
    return true;
}

bool recording_buffer::writeFrame(const uint8_t* data, size_t len) {
    if (!buffering || !activeFile) return false;

    // Write frame length prefix (2 bytes, little-endian) then data
    // This allows reading back individual frames for resending.
    uint16_t frameLen = (uint16_t)len;
    activeFile.write((uint8_t*)&frameLen, 2);
    activeFile.write(data, len);
    return true;
}

void recording_buffer::stopBuffering() {
    if (!buffering) return;

    if (activeFile) {
        activeFile.close();
    }
    buffering = false;
    Serial.println("[RecBuf] Buffering stopped");
}

bool recording_buffer::isBuffering() {
    return buffering;
}

uint8_t recording_buffer::resendPending() {
    if (!sd_storage::isMounted() || !ws_client::isConnected()) return 0;

    File dir = SD.open(BUFFER_DIR);
    if (!dir || !dir.isDirectory()) return 0;

    uint8_t resent = 0;
    uint8_t frameBuf[512];  // Max Opus frame size

    File entry = dir.openNextFile();
    while (entry && resent < MAX_PENDING) {
        if (entry.isDirectory()) {
            entry = dir.openNextFile();
            continue;
        }

        String name = entry.name();
        String fullPath = String(BUFFER_DIR) + "/" + name;
        entry.close();

        // Open and read frame by frame
        File f = SD.open(fullPath, FILE_READ);
        if (!f) {
            entry = dir.openNextFile();
            continue;
        }

        // Send audio:start event for this buffered recording
        ws_client::sendEvent("audio:start", "{\"buffered\":true}");

        uint32_t framesSent = 0;
        while (f.available() >= 2) {
            uint16_t frameLen = 0;
            f.read((uint8_t*)&frameLen, 2);

            if (frameLen == 0 || frameLen > sizeof(frameBuf)) break;
            if (f.available() < frameLen) break;

            f.read(frameBuf, frameLen);
            ws_client::sendBinary(frameBuf, frameLen);
            framesSent++;

            // Small delay to avoid flooding the WebSocket
            vTaskDelay(pdMS_TO_TICKS(5));
        }
        f.close();

        // Send audio:end
        ws_client::sendEvent("audio:end");

        // Delete the file after successful resend
        SD.remove(fullPath);
        resent++;

        Serial.printf("[RecBuf] Resent %s (%u frames)\n", name.c_str(), framesSent);

        entry = dir.openNextFile();
    }
    dir.close();

    if (resent > 0) {
        Serial.printf("[RecBuf] Resent %u buffered recording(s)\n", resent);
    }
    return resent;
}

void recording_buffer::discardPending() {
    if (!sd_storage::isMounted()) return;

    File dir = SD.open(BUFFER_DIR);
    if (!dir || !dir.isDirectory()) return;

    uint8_t deleted = 0;
    File entry = dir.openNextFile();
    while (entry) {
        if (!entry.isDirectory()) {
            String name = entry.name();
            entry.close();
            SD.remove(String(BUFFER_DIR) + "/" + name);
            deleted++;
        }
        entry = dir.openNextFile();
    }
    dir.close();

    if (deleted > 0) {
        Serial.printf("[RecBuf] Discarded %u pending buffer(s)\n", deleted);
    }
}

uint8_t recording_buffer::getPendingCount() {
    if (!sd_storage::isMounted()) return 0;

    File dir = SD.open(BUFFER_DIR);
    if (!dir || !dir.isDirectory()) return 0;

    uint8_t count = 0;
    File entry = dir.openNextFile();
    while (entry) {
        if (!entry.isDirectory()) count++;
        entry = dir.openNextFile();
    }
    dir.close();
    return count;
}
