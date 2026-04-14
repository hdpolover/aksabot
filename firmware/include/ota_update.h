#pragma once
#include <cstdint>
#include <cstddef>

/// OTA firmware update logic.
///
/// Downloads a firmware binary to SD card, verifies its SHA-256 checksum,
/// and flashes it to the inactive OTA partition.
///
/// Flow:
///   1. Backend sends ota:start event with {url, sha256, version}
///   2. Firmware downloads to /ota/firmware.bin (sends ota:progress events)
///   3. SHA-256 verification against expected hash
///   4. Flash from SD to OTA partition (esp_ota_begin/write/end)
///   5. Set boot partition + esp_restart()
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

/// Called periodically during download/verify with the current progress (0-100)
/// and a phase label ("downloading" or "verified").
typedef void (*ProgressCallback)(uint8_t percent, const char* phase);

/// Start an OTA update. Downloads from `url`, verifies SHA-256, then flashes.
/// Blocks the calling task for the entire duration — call from a dedicated task.
/// `progressCb` is called every ~5% during download and after verification.
/// Returns false if already in progress or SD not mounted.
bool start(const char* url, const char* expectedSha256, const char* version,
           ProgressCallback progressCb = nullptr);

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
