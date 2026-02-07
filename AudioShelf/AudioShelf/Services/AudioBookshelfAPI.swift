//
//  AudioBookshelfAPI.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(String)
}

/// Server progress response model for Audiobookshelf API
struct ServerProgress: Codable {
    let id: String?
    let libraryItemId: String
    let episodeId: String
    let duration: Double
    let progress: Double          // 0.0 to 1.0
    let currentTime: Double
    let isFinished: Bool
    let hideFromContinueListening: Bool?
    let lastUpdate: Double?       // Unix timestamp in milliseconds
    let startedAt: Double?
    let finishedAt: Double?
}

@Observable
class AudioBookshelfAPI {
    static let shared = AudioBookshelfAPI()

    private let userDefaults = UserDefaults.standard
    private let serverURLKey = "serverURL"
    private let authTokenKey = "authToken"
    private let cache = OfflineDataCache.shared

    var serverURL: String? {
        get { userDefaults.string(forKey: serverURLKey) }
        set { userDefaults.set(newValue, forKey: serverURLKey) }
    }

    var authToken: String? {
        get { userDefaults.string(forKey: authTokenKey) }
        set { userDefaults.set(newValue, forKey: authTokenKey) }
    }

    var isLoggedIn: Bool {
        serverURL != nil && authToken != nil
    }

    var isOfflineMode: Bool = false

    private init() {}

    // MARK: - Authentication

    func login(serverURL: String, username: String, password: String) async throws -> User {
        var urlString = serverURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }

        guard let url = URL(string: "\(urlString)/login") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = ["username": username, "password": password]
        request.httpBody = try JSONEncoder().encode(credentials)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.unauthorized
        }

        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)

        // Store credentials
        self.serverURL = urlString
        self.authToken = loginResponse.user.token

        return loginResponse.user
    }

    func logout() {
        self.serverURL = nil
        self.authToken = nil
    }

    // MARK: - Libraries

    func getLibraries() async throws -> [Library] {
        guard let serverURL = serverURL, let token = authToken else {
            // If offline, try to use cached data
            if let cachedLibraries = cache.getCachedLibraries() {
                print("🔌 Offline mode: Using cached libraries")
                isOfflineMode = true
                return cachedLibraries
            }
            throw APIError.unauthorized
        }

        guard let url = URL(string: "\(serverURL)/api/libraries") else {
            throw APIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }

            let librariesResponse = try JSONDecoder().decode(LibrariesResponse.self, from: data)

            // Cache the successful response
            cache.cacheLibraries(librariesResponse.libraries)
            isOfflineMode = false

            return librariesResponse.libraries
        } catch {
            // Network error - try cached data
            if let cachedLibraries = cache.getCachedLibraries() {
                print("🔌 Network error: Using cached libraries")
                isOfflineMode = true
                return cachedLibraries
            }
            throw error
        }
    }

    // MARK: - Podcasts

    func getPodcasts(libraryId: String) async throws -> [Podcast] {
        guard let serverURL = serverURL, let token = authToken else {
            // If offline, try to use cached data
            if let cachedPodcasts = cache.getCachedPodcasts() {
                print("🔌 Offline mode: Using cached podcasts")
                isOfflineMode = true
                return cachedPodcasts
            }
            throw APIError.unauthorized
        }

        var components = URLComponents(string: "\(serverURL)/api/libraries/\(libraryId)/items")
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "addedAt"),
            URLQueryItem(name: "desc", value: "1")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }

            let podcastsResponse = try JSONDecoder().decode(PodcastsResponse.self, from: data)

            // Fetch full details for each podcast to get episode data
            // Do this in parallel for better performance
            let podcastsWithEpisodes = await withTaskGroup(of: Podcast?.self, returning: [Podcast].self) { group in
                for podcast in podcastsResponse.results {
                    group.addTask {
                        do {
                            return try await self.getPodcastWithEpisodes(podcastId: podcast.id)
                        } catch {
                            print("Failed to fetch episodes for \(podcast.title): \(error)")
                            return podcast  // Return original podcast without episodes
                        }
                    }
                }

                var results: [Podcast] = []
                for await podcast in group {
                    if let podcast = podcast {
                        results.append(podcast)
                    }
                }
                return results
            }

            // Sort podcasts by latest episode published date, newest first
            let sortedPodcasts = podcastsWithEpisodes.sorted { podcast1, podcast2 in
                // If both have episode dates, compare them
                if let date1 = podcast1.latestEpisodeDate,
                   let date2 = podcast2.latestEpisodeDate {
                    return date1 > date2
                }
                // If only one has a date, it goes first
                if podcast1.latestEpisodeDate != nil {
                    return true
                }
                if podcast2.latestEpisodeDate != nil {
                    return false
                }
                // If neither has dates, fall back to addedAt
                return podcast1.addedAt > podcast2.addedAt
            }

            // Cache the successful response
            cache.cachePodcasts(sortedPodcasts)
            isOfflineMode = false

            return sortedPodcasts
        } catch {
            // Network error - try cached data
            if let cachedPodcasts = cache.getCachedPodcasts() {
                print("🔌 Network error: Using cached podcasts")
                isOfflineMode = true
                return cachedPodcasts
            }
            throw error
        }
    }

    // Helper to fetch full podcast details with episodes
    private func getPodcastWithEpisodes(podcastId: String) async throws -> Podcast {
        guard let serverURL = serverURL, let token = authToken else {
            throw APIError.unauthorized
        }

        guard let url = URL(string: "\(serverURL)/api/items/\(podcastId)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        return try JSONDecoder().decode(Podcast.self, from: data)
    }

    // MARK: - Episodes

    func getEpisodes(podcastId: String) async throws -> [Episode] {
        guard let serverURL = serverURL, let token = authToken else {
            // If offline, try to use cached data
            if let cachedEpisodes = cache.getCachedEpisodes(forPodcastId: podcastId) {
                print("🔌 Offline mode: Using cached episodes for podcast: \(podcastId)")
                isOfflineMode = true
                return cachedEpisodes
            }
            throw APIError.unauthorized
        }

        // Use the correct endpoint: /api/items/{id}
        guard let url = URL(string: "\(serverURL)/api/items/\(podcastId)") else {
            throw APIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }

            // Decode the full podcast item which contains episodes in media.episodes
            let podcast = try JSONDecoder().decode(Podcast.self, from: data)

            guard let episodes = podcast.media.episodes else {
                return []
            }

            // Sort episodes by published date, newest first
            let sortedEpisodes = episodes.sorted { episode1, episode2 in
                guard let date1 = episode1.publishedDate,
                      let date2 = episode2.publishedDate else {
                    return false
                }
                return date1 > date2
            }

            // Cache the successful response
            cache.cacheEpisodes(sortedEpisodes, forPodcastId: podcastId)
            isOfflineMode = false

            return sortedEpisodes
        } catch {
            // Network error - try cached data
            if let cachedEpisodes = cache.getCachedEpisodes(forPodcastId: podcastId) {
                print("🔌 Network error: Using cached episodes for podcast: \(podcastId)")
                isOfflineMode = true
                return cachedEpisodes
            }
            throw error
        }
    }

    // MARK: - Progress Sync

    /// Request body for updating progress
    private struct ProgressUpdateRequest: Encodable {
        let currentTime: Double
        let duration: Double
        let progress: Double          // 0.0 to 1.0
        let isFinished: Bool
    }

    /// Update progress for a podcast episode
    /// API: PATCH /api/me/progress/<libraryItemId>/<episodeId>
    func updateProgress(
        libraryItemId: String,
        episodeId: String,
        currentTime: Double,
        duration: Double,
        isFinished: Bool
    ) async throws {
        guard let serverURL = serverURL, let token = authToken else {
            throw APIError.unauthorized
        }

        let progress = duration > 0 ? currentTime / duration : 0
        let urlString = "\(serverURL)/api/me/progress/\(libraryItemId)/\(episodeId)"
        print("🌐 [API] PATCH \(urlString)")

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = ProgressUpdateRequest(
            currentTime: currentTime,
            duration: duration,
            progress: progress,
            isFinished: isFinished
        )
        let bodyData = try JSONEncoder().encode(body)
        request.httpBody = bodyData

        if let bodyString = String(data: bodyData, encoding: .utf8) {
            print("🌐 [API] Request body: \(bodyString)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("🌐 [API] ❌ Invalid response type")
            throw APIError.invalidResponse
        }

        print("🌐 [API] Response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("🌐 [API] Response body: \(responseString.prefix(500))")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("🌐 [API] ❌ Error status code: \(httpResponse.statusCode)")
            throw APIError.invalidResponse
        }
    }

    /// Get progress for a specific episode
    /// API: GET /api/me/progress/<libraryItemId>/<episodeId>
    func getProgress(
        libraryItemId: String,
        episodeId: String
    ) async throws -> ServerProgress? {
        guard let serverURL = serverURL, let token = authToken else {
            throw APIError.unauthorized
        }

        let urlString = "\(serverURL)/api/me/progress/\(libraryItemId)/\(episodeId)"
        print("🌐 [API] GET \(urlString)")

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("🌐 [API] Response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("🌐 [API] Response body: \(responseString.prefix(500))")
        }

        // 404 means no progress exists yet
        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return try JSONDecoder().decode(ServerProgress.self, from: data)
    }

    /// Get all items currently in progress
    /// API: GET /api/me/items-in-progress
    func getItemsInProgress() async throws -> [ServerProgress] {
        guard let serverURL = serverURL, let token = authToken else {
            throw APIError.unauthorized
        }

        let urlString = "\(serverURL)/api/me/items-in-progress"
        print("🌐 [API] GET \(urlString)")

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("🌐 [API] items-in-progress response: \(responseString.prefix(1000))")
        }

        // The response contains libraryItems with nested mediaProgress
        struct ItemsInProgressResponse: Codable {
            let libraryItems: [LibraryItemInProgress]?
        }

        struct LibraryItemInProgress: Codable {
            let id: String
            let mediaProgress: MediaProgressWrapper?
            let recentEpisode: RecentEpisode?
        }

        struct MediaProgressWrapper: Codable {
            let id: String?
            let libraryItemId: String
            let episodeId: String
            let duration: Double
            let progress: Double
            let currentTime: Double
            let isFinished: Bool
            let hideFromContinueListening: Bool?
            let lastUpdate: Double?
            let startedAt: Double?
            let finishedAt: Double?
        }

        struct RecentEpisode: Codable {
            let id: String
        }

        let decoded = try JSONDecoder().decode(ItemsInProgressResponse.self, from: data)

        return decoded.libraryItems?.compactMap { item -> ServerProgress? in
            guard let mp = item.mediaProgress else { return nil }
            return ServerProgress(
                id: mp.id,
                libraryItemId: mp.libraryItemId,
                episodeId: mp.episodeId,
                duration: mp.duration,
                progress: mp.progress,
                currentTime: mp.currentTime,
                isFinished: mp.isFinished,
                hideFromContinueListening: mp.hideFromContinueListening,
                lastUpdate: mp.lastUpdate,
                startedAt: mp.startedAt,
                finishedAt: mp.finishedAt
            )
        } ?? []
    }

    // MARK: - Cover Images

    func getCoverImageURL(for podcast: Podcast) -> URL? {
        guard let serverURL = serverURL else {
            return nil
        }

        // Use the correct API endpoint for cover images
        // Add the auth token as a query parameter for image loading
        guard let token = authToken else {
            return nil
        }

        var components = URLComponents(string: "\(serverURL)/api/items/\(podcast.id)/cover")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]

        return components?.url
    }
}
