#include "sd_storage.h"
#include "config.h"
#include <Arduino.h>

// This board uses SDIO (4-bit) for the SD card, not SPI.
// SD_MMC is the ESP32 SDIO driver.
#include <SD_MMC.h>

static bool mounted = false;

static const char* DIRS[] = {
    "/cache",
    "/cache/tts",
    "/audio",
    "/audio/resilience",
    "/audio/buffer",
    "/images",
    "/images/remote",
    "/ota",
    "/logs",
};

bool sd_storage::init() {
    // Configure SDIO pins for this board
    SD_MMC.setPins(SD_CLK, SD_CMD, SD_D0, SD_D1, SD_D2, SD_D3);

    if (!SD_MMC.begin("/sdcard", false, false)) {
        Serial.println("[SD] Mount failed — check card");
        // Try 1-bit mode as fallback
        if (!SD_MMC.begin("/sdcard", true, false)) {
            Serial.println("[SD] 1-bit fallback also failed");
            return false;
        }
        Serial.println("[SD] Mounted in 1-bit mode");
    }

    uint8_t cardType = SD_MMC.cardType();
    if (cardType == CARD_NONE) {
        Serial.println("[SD] No card detected");
        return false;
    }

    const char* typeStr = "UNKNOWN";
    switch (cardType) {
        case CARD_MMC:  typeStr = "MMC";   break;
        case CARD_SD:   typeStr = "SD";    break;
        case CARD_SDHC: typeStr = "SDHC";  break;
    }

    uint64_t totalBytes = SD_MMC.totalBytes();
    uint64_t usedBytes = SD_MMC.usedBytes();

    Serial.printf("[SD] Mounted (SDIO) — Type: %s, Size: %lluMB, Used: %lluMB\n",
                  typeStr, totalBytes / (1024 * 1024), usedBytes / (1024 * 1024));

    mounted = true;
    createDirectories();
    return true;
}

bool sd_storage::isMounted() {
    return mounted;
}

void sd_storage::createDirectories() {
    if (!mounted) return;

    for (const char* dir : DIRS) {
        if (!SD_MMC.exists(dir)) {
            if (SD_MMC.mkdir(dir)) {
                Serial.printf("[SD] Created: %s\n", dir);
            } else {
                Serial.printf("[SD] Failed to create: %s\n", dir);
            }
        }
    }
}

uint64_t sd_storage::getFreeBytes() {
    if (!mounted) return 0;
    return SD_MMC.totalBytes() - SD_MMC.usedBytes();
}
