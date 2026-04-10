#pragma once
#include <cstdint>

/// Structured debug logging framework.
///
/// Writes timestamped log entries to Serial and optionally to
/// a rolling file on SD card (/logs/debug.log).
///
/// Usage:
///   LOG_I("WiFi", "Connected to %s", ssid);
///   LOG_W("WS", "Reconnecting (attempt %d)", count);
///   LOG_E("Opus", "Decode failed: %s", opus_strerror(err));
namespace debug_log {

/// Log severity levels.
enum class Level : uint8_t {
    DEBUG,
    INFO,
    WARN,
    ERROR,
};

/// Initialize logging. If SD is mounted, opens the log file.
void init();

/// Write a log entry.
void log(Level level, const char* module, const char* fmt, ...);

/// Flush buffered log entries to SD card.
void flush();

/// Set minimum severity level for SD file logging.
/// Serial always logs everything.
void setFileLevel(Level level);

/// Get the current log file size in bytes.
uint32_t getFileSize();

/// Close and re-open the log file (for rotation testing).
void rotate();

/// Maximum log file size before rotation (default 1 MB).
static const uint32_t MAX_FILE_SIZE = 1024 * 1024;

}  // namespace debug_log

// ── Convenience macros ─────────────────────────────────
#define LOG_D(module, fmt, ...) debug_log::log(debug_log::Level::DEBUG, module, fmt, ##__VA_ARGS__)
#define LOG_I(module, fmt, ...) debug_log::log(debug_log::Level::INFO,  module, fmt, ##__VA_ARGS__)
#define LOG_W(module, fmt, ...) debug_log::log(debug_log::Level::WARN,  module, fmt, ##__VA_ARGS__)
#define LOG_E(module, fmt, ...) debug_log::log(debug_log::Level::ERROR, module, fmt, ##__VA_ARGS__)
