//
//  AudioMetadataCache.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-25.
//

import Foundation

/// Caches audio metadata to avoid waiting for AVPlayer to load duration and other info
class AudioMetadataCache {
    static let shared = AudioMetadataCache()

    private let userDefaults = UserDefaults.standard
    private let cacheKey = "audioMetadataCache"

    private var memoryCache: [String: AudioMetadata] = [:]
    private let queue = DispatchQueue(label: "com.audioshelf.metadatacache", qos: .utility)

    struct AudioMetadata: Codable {
        let episodeId: String
        let duration: Double?
        let fileSize: Int64?
        let cachedAt: Date

        /// Check if cache entry is still valid (7 days)
        var isValid: Bool {
            let maxAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days
            return Date().timeIntervalSince(cachedAt) < maxAge
        }
    }

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Get cached duration for an episode
    func getDuration(episodeId: String) -> Double? {
        queue.sync {
            guard let metadata = memoryCache[episodeId], metadata.isValid else {
                return nil
            }
            return metadata.duration
        }
    }

    /// Get cached file size for an episode
    func getFileSize(episodeId: String) -> Int64? {
        queue.sync {
            guard let metadata = memoryCache[episodeId], metadata.isValid else {
                return nil
            }
            return metadata.fileSize
        }
    }

    /// Cache duration for an episode (usually from AVPlayer after first load)
    func cacheDuration(episodeId: String, duration: Double) {
        queue.async {
            let existing = self.memoryCache[episodeId]
            let metadata = AudioMetadata(
                episodeId: episodeId,
                duration: duration,
                fileSize: existing?.fileSize,
                cachedAt: Date()
            )
            self.memoryCache[episodeId] = metadata
            self.saveToDisk()
        }
    }

    /// Cache file size for an episode (from HTTP response headers)
    func cacheFileSize(episodeId: String, fileSize: Int64) {
        queue.async {
            let existing = self.memoryCache[episodeId]
            let metadata = AudioMetadata(
                episodeId: episodeId,
                duration: existing?.duration,
                fileSize: fileSize,
                cachedAt: Date()
            )
            self.memoryCache[episodeId] = metadata
            self.saveToDisk()
        }
    }

    /// Cache both duration and file size
    func cacheMetadata(episodeId: String, duration: Double?, fileSize: Int64?) {
        queue.async {
            let metadata = AudioMetadata(
                episodeId: episodeId,
                duration: duration,
                fileSize: fileSize,
                cachedAt: Date()
            )
            self.memoryCache[episodeId] = metadata
            self.saveToDisk()
        }
    }

    /// Check if we have valid cached metadata for an episode
    func hasValidCache(episodeId: String) -> Bool {
        queue.sync {
            guard let metadata = memoryCache[episodeId] else {
                return false
            }
            return metadata.isValid && metadata.duration != nil
        }
    }

    /// Clear cache for a specific episode
    func clearCache(episodeId: String) {
        queue.async {
            self.memoryCache.removeValue(forKey: episodeId)
            self.saveToDisk()
        }
    }

    /// Clear all cached metadata
    func clearAllCache() {
        queue.async {
            self.memoryCache.removeAll()
            self.userDefaults.removeObject(forKey: self.cacheKey)
        }
    }

    /// Clean up expired entries
    func cleanupExpiredEntries() {
        queue.async {
            let validEntries = self.memoryCache.filter { $0.value.isValid }
            if validEntries.count != self.memoryCache.count {
                self.memoryCache = validEntries
                self.saveToDisk()
                print("AudioMetadataCache: Cleaned up \(self.memoryCache.count - validEntries.count) expired entries")
            }
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = userDefaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: AudioMetadata].self, from: data) else {
            return
        }
        memoryCache = cache
        print("AudioMetadataCache: Loaded \(cache.count) cached entries")
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(memoryCache) else {
            return
        }
        userDefaults.set(data, forKey: cacheKey)
    }
}
