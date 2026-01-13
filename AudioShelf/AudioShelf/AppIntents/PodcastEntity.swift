//
//  PodcastEntity.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-12.
//

import Foundation
import AppIntents

struct PodcastEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Podcast"

    static var defaultQuery = PodcastQuery()

    var id: String
    var displayString: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)")
    }
}

struct PodcastQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [PodcastEntity.ID]) async throws -> [PodcastEntity] {
        print("DEBUG: entities(for:) called with \(identifiers.count) identifiers")
        // Fetch podcasts by their IDs
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard AudioBookshelfAPI.shared.isLoggedIn else {
                    print("DEBUG: Not logged in")
                    continuation.resume(returning: [])
                    return
                }

                do {
                    let allPodcasts = try await self.fetchAllPodcasts()
                    let filtered = allPodcasts.filter { identifiers.contains($0.id) }
                    print("DEBUG: Found \(filtered.count) matching podcasts")
                    continuation.resume(returning: filtered)
                } catch {
                    print("DEBUG: Error fetching podcasts: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func suggestedEntities() async throws -> [PodcastEntity] {
        print("DEBUG: suggestedEntities() called")
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard AudioBookshelfAPI.shared.isLoggedIn else {
                    print("DEBUG: Not logged in")
                    continuation.resume(returning: [])
                    return
                }

                do {
                    let podcasts = try await self.fetchAllPodcasts()
                    print("DEBUG: Returning \(podcasts.count) suggested podcasts")
                    continuation.resume(returning: podcasts)
                } catch {
                    print("DEBUG: Error fetching podcasts: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func defaultResult() async -> PodcastEntity? {
        print("DEBUG: defaultResult() called")
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                do {
                    let podcasts = try await self.fetchAllPodcasts()
                    let result = podcasts.first
                    print("DEBUG: Returning default podcast: \(result?.displayString ?? "none")")
                    continuation.resume(returning: result)
                } catch {
                    print("DEBUG: Error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func entities(matching string: String) async throws -> [PodcastEntity] {
        print("DEBUG: entities(matching:) called with '\(string)'")
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard AudioBookshelfAPI.shared.isLoggedIn else {
                    print("DEBUG: Not logged in")
                    continuation.resume(returning: [])
                    return
                }

                do {
                    let allPodcasts = try await self.fetchAllPodcasts()
                    print("DEBUG: Total podcasts: \(allPodcasts.count)")

                    // Filter by title matching the search string (case insensitive)
                    let matches = allPodcasts.filter { podcast in
                        podcast.displayString.localizedCaseInsensitiveContains(string)
                    }

                    print("DEBUG: Searching for '\(string)', found \(matches.count) matches")
                    for match in matches {
                        print("DEBUG: - \(match.displayString)")
                    }

                    continuation.resume(returning: matches)
                } catch {
                    print("DEBUG: Error: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    @MainActor
    private func fetchAllPodcasts() async throws -> [PodcastEntity] {
        // Get libraries
        let libraries = try await AudioBookshelfAPI.shared.getLibraries()

        // Find first podcast library
        guard let podcastLibrary = libraries.first(where: { $0.mediaType == "podcast" }) else {
            print("DEBUG: No podcast library found")
            return []
        }

        // Fetch podcasts
        let podcasts = try await AudioBookshelfAPI.shared.getPodcasts(libraryId: podcastLibrary.id)
        print("DEBUG: Fetched \(podcasts.count) podcasts from API")

        // Convert to entities
        return podcasts.map { podcast in
            PodcastEntity(id: podcast.id, displayString: podcast.title)
        }
    }
}
