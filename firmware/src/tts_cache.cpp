#include "tts_cache.h"
#include "sd_storage.h"
#include <SD_MMC.h>
#define SD SD_MMC
#include <ArduinoJson.h>
#include <Arduino.h>

// ── Constants ──────────────────────────────────────────
static const char* CACHE_DIR = "/cache/tts";
static const char* MANIFEST_PATH = "/cache/tts/manifest.json";

// ── In-memory manifest ─────────────────────────────────
// Kept in RAM for fast lookup. Persisted to SD on changes.
static const uint16_t MAX_ENTRIES = 512;

struct CacheEntry {
    char hash[17];          // 16-char SHA256 prefix + null
    uint32_t sizeBytes;     // File size
    uint32_t lastUsed;      // millis() timestamp of last access
    bool valid;             // Entry is active
};

static CacheEntry entries[MAX_ENTRIES];
static uint16_t entryCount = 0;
static uint64_t totalSize = 0;
static bool initialized = false;

// ── Helpers ────────────────────────────────────────────

static void buildFilePath(const char* hash, char* buf, size_t bufLen) {
    snprintf(buf, bufLen, "%s/%s.opus", CACHE_DIR, hash);
}

static int findEntry(const char* hash) {
    for (uint16_t i = 0; i < MAX_ENTRIES; i++) {
        if (entries[i].valid && strcmp(entries[i].hash, hash) == 0) {
            return i;
        }
    }
    return -1;
}

static int findFreeSlot() {
    for (uint16_t i = 0; i < MAX_ENTRIES; i++) {
        if (!entries[i].valid) return i;
    }
    return -1;
}

static int findLruEntry() {
    int lruIdx = -1;
    uint32_t oldest = UINT32_MAX;
    for (uint16_t i = 0; i < MAX_ENTRIES; i++) {
        if (entries[i].valid && entries[i].lastUsed < oldest) {
            oldest = entries[i].lastUsed;
            lruIdx = i;
        }
    }
    return lruIdx;
}

static bool saveManifest() {
    if (!sd_storage::isMounted()) return false;

    File f = SD.open(MANIFEST_PATH, FILE_WRITE);
    if (!f) {
        Serial.println("[Cache] Failed to write manifest");
        return false;
    }

    // Write as JSON array
    f.print('[');
    bool first = true;
    for (uint16_t i = 0; i < MAX_ENTRIES; i++) {
        if (!entries[i].valid) continue;
        if (!first) f.print(',');
        first = false;

        f.printf("{\"h\":\"%s\",\"s\":%u,\"t\":%u}",
            entries[i].hash, entries[i].sizeBytes, entries[i].lastUsed);
    }
    f.print(']');
    f.close();
    return true;
}

static bool loadManifest() {
    if (!sd_storage::isMounted()) return false;
    if (!SD.exists(MANIFEST_PATH)) return true;  // No manifest yet — ok

    File f = SD.open(MANIFEST_PATH, FILE_READ);
    if (!f) return false;

    // Read entire file into buffer (manifest is small)
    size_t fileSize = f.size();
    if (fileSize == 0 || fileSize > 64 * 1024) {
        f.close();
        return false;
    }

    char* buf = (char*)ps_malloc(fileSize + 1);
    if (!buf) {
        f.close();
        return false;
    }
    f.readBytes(buf, fileSize);
    buf[fileSize] = '\0';
    f.close();

    // Parse JSON array
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, buf);
    free(buf);

    if (err) {
        Serial.printf("[Cache] Manifest parse error: %s\n", err.c_str());
        return false;
    }

    JsonArray arr = doc.as<JsonArray>();
    entryCount = 0;
    totalSize = 0;

    for (JsonObject obj : arr) {
        if (entryCount >= MAX_ENTRIES) break;

        const char* h = obj["h"] | "";
        uint32_t s = obj["s"] | 0;
        uint32_t t = obj["t"] | 0;

        if (strlen(h) == 0) continue;

        strncpy(entries[entryCount].hash, h, 16);
        entries[entryCount].hash[16] = '\0';
        entries[entryCount].sizeBytes = s;
        entries[entryCount].lastUsed = t;
        entries[entryCount].valid = true;
        totalSize += s;
        entryCount++;
    }

    Serial.printf("[Cache] Loaded manifest: %u entries, %lluKB\n",
        entryCount, totalSize / 1024);
    return true;
}

// ── Public API ─────────────────────────────────────────

bool tts_cache::init() {
    if (initialized) return true;
    if (!sd_storage::isMounted()) {
        Serial.println("[Cache] SD not mounted — cache disabled");
        return false;
    }

    memset(entries, 0, sizeof(entries));
    entryCount = 0;
    totalSize = 0;

    loadManifest();
    initialized = true;
    return true;
}

bool tts_cache::lookup(const char* hash, char* pathBuf, size_t pathBufLen) {
    if (!initialized) return false;

    int idx = findEntry(hash);
    if (idx < 0) return false;

    buildFilePath(hash, pathBuf, pathBufLen);

    // Verify file actually exists on SD
    if (!SD.exists(pathBuf)) {
        // Stale manifest entry — remove it
        entries[idx].valid = false;
        totalSize -= entries[idx].sizeBytes;
        entryCount--;
        saveManifest();
        return false;
    }

    return true;
}

bool tts_cache::save(const char* hash, const uint8_t* data, size_t dataLen) {
    if (!initialized || !sd_storage::isMounted()) return false;

    // Check if already cached
    if (findEntry(hash) >= 0) return true;

    // Evict if needed before saving
    evictIfNeeded();

    // Find a free slot
    int slot = findFreeSlot();
    if (slot < 0) {
        // All slots full — evict LRU
        int lru = findLruEntry();
        if (lru < 0) return false;

        char oldPath[64];
        buildFilePath(entries[lru].hash, oldPath, sizeof(oldPath));
        SD.remove(oldPath);
        totalSize -= entries[lru].sizeBytes;
        entries[lru].valid = false;
        entryCount--;
        slot = lru;
    }

    // Write file to SD
    char path[64];
    buildFilePath(hash, path, sizeof(path));

    File f = SD.open(path, FILE_WRITE);
    if (!f) {
        Serial.printf("[Cache] Failed to write %s\n", path);
        return false;
    }
    f.write(data, dataLen);
    f.close();

    // Update manifest entry
    strncpy(entries[slot].hash, hash, 16);
    entries[slot].hash[16] = '\0';
    entries[slot].sizeBytes = dataLen;
    entries[slot].lastUsed = millis();
    entries[slot].valid = true;
    totalSize += dataLen;
    entryCount++;

    saveManifest();

    Serial.printf("[Cache] Saved %s (%u bytes, total %u entries)\n",
        hash, (uint32_t)dataLen, entryCount);
    return true;
}

void tts_cache::touch(const char* hash) {
    int idx = findEntry(hash);
    if (idx >= 0) {
        entries[idx].lastUsed = millis();
        // Don't persist on every touch — batched with next save
    }
}

bool tts_cache::invalidate(const char* hash) {
    if (!initialized) return false;

    int idx = findEntry(hash);
    if (idx < 0) return false;

    char path[64];
    buildFilePath(hash, path, sizeof(path));
    SD.remove(path);

    totalSize -= entries[idx].sizeBytes;
    entries[idx].valid = false;
    entryCount--;

    saveManifest();
    Serial.printf("[Cache] Invalidated %s\n", hash);
    return true;
}

bool tts_cache::invalidateAll() {
    if (!initialized) return false;

    for (uint16_t i = 0; i < MAX_ENTRIES; i++) {
        if (!entries[i].valid) continue;

        char path[64];
        buildFilePath(entries[i].hash, path, sizeof(path));
        SD.remove(path);
        entries[i].valid = false;
    }

    entryCount = 0;
    totalSize = 0;
    saveManifest();
    Serial.println("[Cache] All entries invalidated");
    return true;
}

void tts_cache::evictIfNeeded() {
    while (totalSize > MAX_CACHE_BYTES && entryCount > 0) {
        int lru = findLruEntry();
        if (lru < 0) break;

        char path[64];
        buildFilePath(entries[lru].hash, path, sizeof(path));
        SD.remove(path);

        Serial.printf("[Cache] Evicted %s (%u bytes)\n",
            entries[lru].hash, entries[lru].sizeBytes);

        totalSize -= entries[lru].sizeBytes;
        entries[lru].valid = false;
        entryCount--;
    }

    saveManifest();
}

uint64_t tts_cache::getTotalSizeBytes() {
    return totalSize;
}

uint16_t tts_cache::getEntryCount() {
    return entryCount;
}
