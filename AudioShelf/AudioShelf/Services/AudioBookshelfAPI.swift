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

@Observable
class AudioBookshelfAPI {
    static let shared = AudioBookshelfAPI()

    private let userDefaults = UserDefaults.standard
    private let serverURLKey = "serverURL"
    private let authTokenKey = "authToken"

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
            throw APIError.unauthorized
        }

        guard let url = URL(string: "\(serverURL)/api/libraries") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let librariesResponse = try JSONDecoder().decode(LibrariesResponse.self, from: data)
        return librariesResponse.libraries
    }

    // MARK: - Podcasts

    func getPodcasts(libraryId: String) async throws -> [Podcast] {
        guard let serverURL = serverURL, let token = authToken else {
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

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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

        return sortedPodcasts
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
            throw APIError.unauthorized
        }

        // Use the correct endpoint: /api/items/{id}
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

        return sortedEpisodes
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
