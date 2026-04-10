#pragma once
#include <cstdint>
#include <cstddef>

/// TTS audio cache on MicroSD card.
///
/// Stores Opus-encoded audio keyed by SHA256 hash (first 16 chars).
/// Uses a manifest file to track entries and LRU eviction.
///
/// Directory structure:
///   /cache/tts/manifest.json
///   /cache/tts/<hash>.opus
///
/// The backend sends a `cacheKey` with each TTS response. The firmware
/// checks the local cache first before playing from the network.
namespace tts_cache {

/// Initialize cache — loads manifest from SD if present.
bool init();

/// Check if a cache entry exists for the given hash.
/// Returns true and fills `path` with the file path if found.
bool lookup(const char* hash, char* pathBuf, size_t pathBufLen);

/// Save audio data to cache under the given hash.
/// Updates manifest with entry metadata.
bool save(const char* hash, const uint8_t* data, size_t dataLen);

/// Mark an entry as recently used (bump LRU timestamp).
void touch(const char* hash);

/// Invalidate (delete) a specific cache entry.
bool invalidate(const char* hash);

/// Invalidate all cache entries. Called on personality change.
bool invalidateAll();

/// Run LRU eviction if cache exceeds the size limit.
/// Deletes least-recently-used entries until under the limit.
void evictIfNeeded();

/// Get the total size of cached audio files (bytes).
uint64_t getTotalSizeBytes();

/// Get the number of cached entries.
uint16_t getEntryCount();

/// Maximum cache size in bytes (default 100 MB).
static const uint64_t MAX_CACHE_BYTES = 100ULL * 1024 * 1024;

}  // namespace tts_cache
