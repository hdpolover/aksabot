#include "sd_storage.h"
#include "config.h"
#include <SD.h>
#include <SPI.h>
#include <Arduino.h>

static bool mounted = false;

static const char* DIRS[] = {
    "/cache",
    "/cache/tts",
    "/audio",
    "/audio/resilience",
    "/audio/buffer",
    "/ota",
    "/logs",
};

bool sd_storage::init() {
    SPI.begin(SPI_CLK, SPI_MISO, SPI_MOSI, SD_CS);

    if (!SD.begin(SD_CS)) {
        Serial.println("[SD] Mount failed — check card and wiring");
        return false;
    }

    uint8_t cardType = SD.cardType();
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

    uint64_t totalBytes = SD.totalBytes();
    uint64_t usedBytes = SD.usedBytes();

    Serial.printf("[SD] Mounted — Type: %s, Size: %lluMB, Used: %lluMB\n",
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
        if (!SD.exists(dir)) {
            if (SD.mkdir(dir)) {
                Serial.printf("[SD] Created: %s\n", dir);
            } else {
                Serial.printf("[SD] Failed to create: %s\n", dir);
            }
        }
    }
}

uint64_t sd_storage::getFreeBytes() {
    if (!mounted) return 0;
    return SD.totalBytes() - SD.usedBytes();
}
