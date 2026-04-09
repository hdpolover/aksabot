#pragma once
#include <cstdint>

namespace sd_storage {

/// Initialize MicroSD card via SPI and mount FAT32 filesystem.
/// Creates the directory structure if it doesn't exist.
/// Returns true on success.
bool init();

/// Returns true if SD card is mounted and accessible.
bool isMounted();

/// Create required directory structure on SD card.
void createDirectories();

/// Get free space in bytes.
uint64_t getFreeBytes();

}  // namespace sd_storage
