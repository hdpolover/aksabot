#include "ota_update.h"
#include "sd_storage.h"
#include <SD_MMC.h>
#define SD SD_MMC
#include <HTTPClient.h>
#include <mbedtls/sha256.h>
#include <Arduino.h>

static const char* OTA_PATH = "/ota/firmware.bin";
static const size_t DOWNLOAD_BUF_SIZE = 4096;

// ── Internal state ─────────────────────────────────────
static ota_update::State state = ota_update::State::IDLE;
static char errorMsg[64] = {};
static uint8_t progress = 0;
static char expectedHash[65] = {};  // 64 hex chars + null
static char stagedVersion[32] = {};

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

bool ota_update::start(const char* url, const char* expectedSha256, const char* version) {
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

    WiFiClient* stream = http.getStreamPtr();
    uint8_t buf[DOWNLOAD_BUF_SIZE];
    int totalRead = 0;

    while (http.connected() && totalRead < contentLength) {
        size_t available = stream->available();
        if (available == 0) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        size_t toRead = min(available, sizeof(buf));
        size_t bytesRead = stream->readBytes(buf, toRead);
        outFile.write(buf, bytesRead);
        totalRead += bytesRead;

        progress = (uint8_t)((totalRead * 100L) / contentLength);
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
        // TODO: Cancel in-progress HTTP download
    }
    state = State::IDLE;
    progress = 0;
    SD.remove(OTA_PATH);
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

    // TODO: Hardware-dependent flash operation
    // Use esp_ota_begin(), esp_ota_write(), esp_ota_end()
    // Read from /ota/firmware.bin in chunks and write to OTA partition
    // On success: esp_ota_set_boot_partition(), esp_restart()
    // On failure: rollback to factory partition

    Serial.println("[OTA] apply() — flash operation not yet implemented (needs hardware)");
    strncpy(errorMsg, "Flash not implemented — needs hardware", sizeof(errorMsg));
    state = State::ERROR;
    return false;
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
