#include "ota_update.h"
#include "sd_storage.h"
#include <SD_MMC.h>
#define SD SD_MMC
#include <WiFi.h>
#include <HTTPClient.h>
#include <mbedtls/sha256.h>
#include <esp_ota_ops.h>
#include <esp_partition.h>
#include <Arduino.h>

static const char* OTA_PATH = "/ota/firmware.bin";
static const size_t DOWNLOAD_BUF_SIZE = 4096;

// ── Internal state ─────────────────────────────────────
static ota_update::State state = ota_update::State::IDLE;
static char errorMsg[64] = {};
static uint8_t progress = 0;
static char expectedHash[65] = {};  // 64 hex chars + null
static char stagedVersion[32] = {};
static volatile bool cancelRequested = false;

// ── Helpers ────────────────────────────────────────────

/// Convert SHA-256 binary digest to hex string.
static void digestToHex(const uint8_t* digest, char* hexBuf) {
    for (int i = 0; i < 32; i++) {
        sprintf(hexBuf + (i * 2), "%02x", digest[i]);
    }
    hexBuf[64] = '\0';
}

/// Compute SHA-256 of a file on SD card.
static bool computeFileSha256(const char* path, char* hexOut) {
    File f = SD.open(path, FILE_READ);
    if (!f) return false;

    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0);  // 0 = SHA-256 (not SHA-224)

    uint8_t buf[512];
    while (f.available()) {
        size_t read = f.read(buf, sizeof(buf));
        if (read > 0) {
            mbedtls_sha256_update(&ctx, buf, read);
        }
    }
    f.close();

    uint8_t digest[32];
    mbedtls_sha256_finish(&ctx, digest);
    mbedtls_sha256_free(&ctx);

    digestToHex(digest, hexOut);
    return true;
}

// ── Public API ─────────────────────────────────────────

void ota_update::init() {
    state = State::IDLE;
    progress = 0;
    errorMsg[0] = '\0';

    // Check if a staged firmware exists from a previous attempt
    if (sd_storage::isMounted() && SD.exists(OTA_PATH)) {
        Serial.println("[OTA] Found staged firmware from previous session");
    }
}

bool ota_update::start(const char* url, const char* expectedSha256, const char* version,
                       ProgressCallback progressCb) {
    if (state == State::DOWNLOADING || state == State::FLASHING) {
        return false;  // Already in progress
    }
    if (!sd_storage::isMounted()) {
        strncpy(errorMsg, "SD card not mounted", sizeof(errorMsg));
        state = State::ERROR;
        return false;
    }

    strncpy(expectedHash, expectedSha256, sizeof(expectedHash) - 1);
    strncpy(stagedVersion, version, sizeof(stagedVersion) - 1);
    state = State::DOWNLOADING;
    progress = 0;
    cancelRequested = false;

    Serial.printf("[OTA] Starting download: %s (version %s)\n", url, version);

    // Download firmware to SD
    HTTPClient http;
    http.begin(url);
    int httpCode = http.GET();

    if (httpCode != 200) {
        snprintf(errorMsg, sizeof(errorMsg), "HTTP %d", httpCode);
        state = State::ERROR;
        http.end();
        Serial.printf("[OTA] Download failed: %s\n", errorMsg);
        return false;
    }

    int contentLength = http.getSize();
    if (contentLength <= 0) {
        strncpy(errorMsg, "Invalid content length", sizeof(errorMsg));
        state = State::ERROR;
        http.end();
        return false;
    }

    // Remove old staged firmware if any
    if (SD.exists(OTA_PATH)) {
        SD.remove(OTA_PATH);
    }

    File outFile = SD.open(OTA_PATH, FILE_WRITE);
    if (!outFile) {
        strncpy(errorMsg, "Failed to create firmware file", sizeof(errorMsg));
        state = State::ERROR;
        http.end();
        return false;
    }

    WiFiClient* httpStream = http.getStreamPtr();
    uint8_t buf[DOWNLOAD_BUF_SIZE];
    int totalRead = 0;
    uint8_t lastReportedPct = 255;  // Force first callback at 0%

    while (http.connected() && totalRead < contentLength) {
        if (cancelRequested) {
            outFile.close();
            http.end();
            SD.remove(OTA_PATH);
            state = State::IDLE;
            Serial.println("[OTA] Download cancelled");
            return false;
        }

        size_t available = httpStream->available();
        if (available == 0) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        size_t toRead = min(available, sizeof(buf));
        size_t bytesRead = httpStream->readBytes(buf, toRead);
        outFile.write(buf, bytesRead);
        totalRead += bytesRead;

        progress = (uint8_t)((totalRead * 100L) / contentLength);

        // Report every 5% to avoid flooding the WS connection
        if (progressCb && (progress / 5) != (lastReportedPct / 5)) {
            progressCb(progress, "downloading");
            lastReportedPct = progress;
        }
    }

    outFile.close();
    http.end();

    if (totalRead < contentLength) {
        strncpy(errorMsg, "Download incomplete", sizeof(errorMsg));
        state = State::ERROR;
        SD.remove(OTA_PATH);
        return false;
    }

    Serial.printf("[OTA] Downloaded %d bytes\n", totalRead);

    // Verify SHA-256
    state = State::VERIFYING;
    progress = 0;

    char computedHash[65];
    if (!computeFileSha256(OTA_PATH, computedHash)) {
        strncpy(errorMsg, "SHA-256 computation failed", sizeof(errorMsg));
        state = State::ERROR;
        SD.remove(OTA_PATH);
        return false;
    }

    if (strcasecmp(computedHash, expectedHash) != 0) {
        snprintf(errorMsg, sizeof(errorMsg), "SHA-256 mismatch");
        state = State::ERROR;
        SD.remove(OTA_PATH);
        Serial.printf("[OTA] Hash mismatch!\n  Expected: %s\n  Got:      %s\n",
            expectedHash, computedHash);
        return false;
    }

    Serial.printf("[OTA] Verified: %s\n", computedHash);
    state = State::READY;
    progress = 100;
    if (progressCb) progressCb(100, "verified");
    return true;
}

ota_update::State ota_update::getState() {
    return state;
}

const char* ota_update::getError() {
    return errorMsg;
}

uint8_t ota_update::getProgress() {
    return progress;
}

void ota_update::cancel() {
    if (state == State::DOWNLOADING) {
        // Signal the download loop to abort on next iteration (~10ms latency)
        cancelRequested = true;
        return;  // Loop will clean up and reset state
    }
    state = State::IDLE;
    progress = 0;
    if (SD.exists(OTA_PATH)) SD.remove(OTA_PATH);
    Serial.println("[OTA] Cancelled");
}

bool ota_update::apply() {
    if (state != State::READY) return false;
    if (!SD.exists(OTA_PATH)) {
        strncpy(errorMsg, "Staged firmware not found", sizeof(errorMsg));
        state = State::ERROR;
        return false;
    }

    state = State::FLASHING;
    progress = 0;

    // Find next OTA partition (alternates between ota_0 and ota_1)
    const esp_partition_t* updatePart = esp_ota_get_next_update_partition(NULL);
    if (!updatePart) {
        strncpy(errorMsg, "No OTA partition found", sizeof(errorMsg));
        state = State::ERROR;
        Serial.println("[OTA] ERROR: No OTA partition available — check partition table");
        return false;
    }
    Serial.printf("[OTA] Target partition: %s (offset 0x%08" PRIx32 ", size 0x%08" PRIx32 ")\n",
        updatePart->label, updatePart->address, updatePart->size);

    // Open the staged firmware
    File fwFile = SD.open(OTA_PATH, FILE_READ);
    if (!fwFile) {
        strncpy(errorMsg, "Cannot open staged firmware", sizeof(errorMsg));
        state = State::ERROR;
        return false;
    }
    size_t fwSize = fwFile.size();
    if (fwSize == 0 || fwSize > updatePart->size) {
        snprintf(errorMsg, sizeof(errorMsg), "Firmware size %u invalid", (unsigned)fwSize);
        state = State::ERROR;
        fwFile.close();
        return false;
    }

    // Begin OTA — OTA_WITH_SEQUENTIAL_WRITES lets ESP-IDF validate the image header
    esp_ota_handle_t otaHandle;
    esp_err_t err = esp_ota_begin(updatePart, OTA_WITH_SEQUENTIAL_WRITES, &otaHandle);
    if (err != ESP_OK) {
        snprintf(errorMsg, sizeof(errorMsg), "esp_ota_begin: %s", esp_err_to_name(err));
        state = State::ERROR;
        fwFile.close();
        Serial.printf("[OTA] ERROR: %s\n", errorMsg);
        return false;
    }

    // Write firmware in chunks
    static uint8_t flashBuf[4096];
    size_t totalWritten = 0;

    while (fwFile.available()) {
        size_t bytesRead = fwFile.read(flashBuf, sizeof(flashBuf));
        if (bytesRead == 0) break;

        err = esp_ota_write(otaHandle, flashBuf, bytesRead);
        if (err != ESP_OK) {
            snprintf(errorMsg, sizeof(errorMsg), "esp_ota_write: %s", esp_err_to_name(err));
            esp_ota_abort(otaHandle);
            fwFile.close();
            SD.remove(OTA_PATH);
            state = State::ERROR;
            Serial.printf("[OTA] Write error at offset %u: %s\n", (unsigned)totalWritten, esp_err_to_name(err));
            return false;
        }

        totalWritten += bytesRead;
        progress = (uint8_t)((totalWritten * 100UL) / fwSize);
    }
    fwFile.close();

    if (totalWritten != fwSize) {
        snprintf(errorMsg, sizeof(errorMsg), "Write incomplete (%u/%u bytes)", (unsigned)totalWritten, (unsigned)fwSize);
        esp_ota_abort(otaHandle);
        SD.remove(OTA_PATH);
        state = State::ERROR;
        Serial.printf("[OTA] ERROR: %s\n", errorMsg);
        return false;
    }

    // Finalise — ESP-IDF validates the image checksum internally
    err = esp_ota_end(otaHandle);
    if (err != ESP_OK) {
        snprintf(errorMsg, sizeof(errorMsg), "esp_ota_end: %s", esp_err_to_name(err));
        state = State::ERROR;
        SD.remove(OTA_PATH);
        Serial.printf("[OTA] Validation failed: %s\n", esp_err_to_name(err));
        return false;
    }

    // Mark partition as the boot target
    err = esp_ota_set_boot_partition(updatePart);
    if (err != ESP_OK) {
        snprintf(errorMsg, sizeof(errorMsg), "set_boot_partition: %s", esp_err_to_name(err));
        state = State::ERROR;
        SD.remove(OTA_PATH);
        Serial.printf("[OTA] ERROR: %s\n", errorMsg);
        return false;
    }

    SD.remove(OTA_PATH);  // Clean up — no longer needed after successful flash

    Serial.printf("[OTA] Flash complete (%u bytes). Rebooting into %s...\n",
        (unsigned)totalWritten, updatePart->label);

    progress = 100;
    delay(500);   // Brief pause so the log line flushes over serial
    esp_restart();

    return true;  // unreachable — esp_restart() doesn't return
}

bool ota_update::hasStagedFirmware() {
    return sd_storage::isMounted() && SD.exists(OTA_PATH);
}

void ota_update::clearStaged() {
    if (sd_storage::isMounted()) {
        SD.remove(OTA_PATH);
    }
    state = State::IDLE;
    progress = 0;
}
