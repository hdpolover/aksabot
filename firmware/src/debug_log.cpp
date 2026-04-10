#include "debug_log.h"
#include "sd_storage.h"
#include <SD_MMC.h>
#define SD SD_MMC
#include <Arduino.h>
#include <cstdarg>

static const char* LOG_PATH = "/logs/debug.log";
static const char* LOG_PATH_OLD = "/logs/debug.log.old";

static debug_log::Level fileLevel = debug_log::Level::INFO;
static bool fileEnabled = false;
static bool initialized = false;

static const char* levelStr(debug_log::Level level) {
    switch (level) {
        case debug_log::Level::DEBUG: return "D";
        case debug_log::Level::INFO:  return "I";
        case debug_log::Level::WARN:  return "W";
        case debug_log::Level::ERROR: return "E";
        default: return "?";
    }
}

// ── Public API ─────────────────────────────────────────

void debug_log::init() {
    if (initialized) return;
    initialized = true;

    if (sd_storage::isMounted()) {
        fileEnabled = true;

        // Check file size and rotate if needed
        if (SD.exists(LOG_PATH)) {
            File f = SD.open(LOG_PATH, FILE_READ);
            if (f) {
                if (f.size() > MAX_FILE_SIZE) {
                    f.close();
                    // Rotate: delete old backup, rename current to .old
                    SD.remove(LOG_PATH_OLD);
                    SD.rename(LOG_PATH, LOG_PATH_OLD);
                    Serial.println("[Log] Rotated log file");
                } else {
                    f.close();
                }
            }
        }

        Serial.println("[Log] File logging enabled → /logs/debug.log");
    } else {
        Serial.println("[Log] SD not mounted — serial only");
    }
}

void debug_log::log(Level level, const char* module, const char* fmt, ...) {
    // Format the message
    char msgBuf[256];
    va_list args;
    va_start(args, fmt);
    vsnprintf(msgBuf, sizeof(msgBuf), fmt, args);
    va_end(args);

    // Timestamp
    uint32_t ms = millis();
    uint32_t sec = ms / 1000;
    uint32_t min = sec / 60;
    uint32_t hr = min / 60;

    // Always print to Serial
    Serial.printf("[%02u:%02u:%02u.%03u] [%s] [%s] %s\n",
        (uint8_t)(hr % 24), (uint8_t)(min % 60), (uint8_t)(sec % 60),
        (uint16_t)(ms % 1000), levelStr(level), module, msgBuf);

    // Write to file if enabled and level is sufficient
    if (fileEnabled && level >= fileLevel) {
        File f = SD.open(LOG_PATH, FILE_APPEND);
        if (f) {
            f.printf("[%02u:%02u:%02u.%03u] [%s] [%s] %s\n",
                (uint8_t)(hr % 24), (uint8_t)(min % 60), (uint8_t)(sec % 60),
                (uint16_t)(ms % 1000), levelStr(level), module, msgBuf);
            f.close();
        }
    }
}

void debug_log::flush() {
    // SD FAT32 writes are synchronous on ESP32 — nothing to flush
    // This exists for API completeness and future buffered writes
}

void debug_log::setFileLevel(Level level) {
    fileLevel = level;
}

uint32_t debug_log::getFileSize() {
    if (!fileEnabled || !SD.exists(LOG_PATH)) return 0;

    File f = SD.open(LOG_PATH, FILE_READ);
    if (!f) return 0;
    uint32_t size = f.size();
    f.close();
    return size;
}

void debug_log::rotate() {
    if (!fileEnabled) return;

    SD.remove(LOG_PATH_OLD);
    if (SD.exists(LOG_PATH)) {
        SD.rename(LOG_PATH, LOG_PATH_OLD);
    }
    Serial.println("[Log] Manual rotation");
}
