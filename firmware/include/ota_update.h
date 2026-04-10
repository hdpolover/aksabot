#pragma once
#include <cstdint>
#include <cstddef>

/// OTA firmware update logic.
///
/// Downloads a firmware binary to SD card, verifies its SHA-256 checksum,
/// and stages it for flashing. The actual flash operation (esp_ota_begin)
/// is hardware-dependent and marked as TODO.
///
/// Flow:
///   1. Backend sends ota:start event with {url, sha256, version}
///   2. Firmware downloads to /ota/firmware.bin
///   3. SHA-256 verification against expected hash
///   4. Flash from SD to OTA partition (TODO — needs hardware)
///   5. Report status back to backend
namespace ota_update {

/// OTA state.
enum class State : uint8_t {
    IDLE,
    DOWNLOADING,
    VERIFYING,
    READY,          // Verified and ready to flash
    FLASHING,       // Writing to OTA partition (hardware)
    COMPLETE,
    ERROR,
};

/// Initialize OTA subsystem.
void init();

/// Start an OTA update. Downloads from `url` and verifies against `expectedSha256`.
/// Non-blocking — check getState() for progress.
/// Returns false if already in progress or SD not mounted.
bool start(const char* url, const char* expectedSha256, const char* version);

/// Get current OTA state.
State getState();

/// Get error message (valid when state == ERROR).
const char* getError();

/// Get download progress (0-100).
uint8_t getProgress();

/// Cancel an in-progress OTA update.
void cancel();

/// Apply a verified update (flash from SD).
/// TODO: Hardware-dependent — needs esp_ota_begin/write/end.
bool apply();

/// Check if a staged firmware file exists on SD.
bool hasStagedFirmware();

/// Delete the staged firmware file.
void clearStaged();

}  // namespace ota_update
