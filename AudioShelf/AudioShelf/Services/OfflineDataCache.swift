//
//  OfflineDataCache.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-09.
//

import Foundation

class OfflineDataCache {
    static let shared = OfflineDataCache()

    private let userDefaults = UserDefaults.standard
    private let podcastsKey = "cachedPodcasts"
    private let episodesKey = "cachedEpisodes"
    private let librariesKey = "cachedLibraries"
    private let lastUpdateKey = "cacheLastUpdate"

    private init() {}

    // MARK: - Podcasts Cache

    func cachePodcasts(_ podcasts: [Podcast]) {
        if let encoded = try? JSONEncoder().encode(podcasts) {
            userDefaults.set(encoded, forKey: podcastsKey)
            userDefaults.set(Date(), forKey: lastUpdateKey)
            print("📦 Cached \(podcasts.count) podcasts")
        }
    }

    func getCachedPodcasts() -> [Podcast]? {
        guard let data = userDefaults.data(forKey: podcastsKey),
              let podcasts = try? JSONDecoder().decode([Podcast].self, from: data) else {
            return nil
        }
        print("📦 Retrieved \(podcasts.count) cached podcasts")
        return podcasts
    }

    // MARK: - Episodes Cache

    func cacheEpisodes(_ episodes: [Episode], forPodcastId podcastId: String) {
        var allEpisodes = getAllCachedEpisodes()
        allEpisodes[podcastId] = episodes

        if let encoded = try? JSONEncoder().encode(allEpisodes) {
            userDefaults.set(encoded, forKey: episodesKey)
            print("📦 Cached \(episodes.count) episodes for podcast: \(podcastId)")
        }
    }

    func getCachedEpisodes(forPodcastId podcastId: String) -> [Episode]? {
        let allEpisodes = getAllCachedEpisodes()
        let episodes = allEpisodes[podcastId]
        if let episodes = episodes {
            print("📦 Retrieved \(episodes.count) cached episodes for podcast: \(podcastId)")
        }
        return episodes
    }

    private func getAllCachedEpisodes() -> [String: [Episode]] {
        guard let data = userDefaults.data(forKey: episodesKey),
              let episodes = try? JSONDecoder().decode([String: [Episode]].self, from: data) else {
            return [:]
        }
        return episodes
    }

    // MARK: - Libraries Cache

    func cacheLibraries(_ libraries: [Library]) {
        if let encoded = try? JSONEncoder().encode(libraries) {
            userDefaults.set(encoded, forKey: librariesKey)
            print("📦 Cached \(libraries.count) libraries")
        }
    }

    func getCachedLibraries() -> [Library]? {
        guard let data = userDefaults.data(forKey: librariesKey),
              let libraries = try? JSONDecoder().decode([Library].self, from: data) else {
            return nil
        }
        print("📦 Retrieved \(libraries.count) cached libraries")
        return libraries
    }

    // MARK: - Cache Info

    func getLastUpdateDate() -> Date? {
        return userDefaults.object(forKey: lastUpdateKey) as? Date
    }

    func hasCachedData() -> Bool {
        return getCachedPodcasts() != nil
    }

    func clearCache() {
        userDefaults.removeObject(forKey: podcastsKey)
        userDefaults.removeObject(forKey: episodesKey)
        userDefaults.removeObject(forKey: librariesKey)
        userDefaults.removeObject(forKey: lastUpdateKey)
        print("📦 Cache cleared")
    }
}
