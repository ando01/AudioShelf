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

struct PodcastQuery: EntityQuery {
    func entities(for identifiers: [PodcastEntity.ID]) async throws -> [PodcastEntity] {
        // Fetch podcasts by their IDs
        guard AudioBookshelfAPI.shared.isLoggedIn else {
            return []
        }

        // Get all podcasts and filter by identifiers
        let allPodcasts = try await fetchAllPodcasts()
        return allPodcasts.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PodcastEntity] {
        // Return list of user's podcasts for suggestions
        guard AudioBookshelfAPI.shared.isLoggedIn else {
            return []
        }

        return try await fetchAllPodcasts()
    }

    func defaultResult() async -> PodcastEntity? {
        // Return the most recently updated podcast
        return try? await fetchAllPodcasts().first
    }

    @MainActor
    private func fetchAllPodcasts() async throws -> [PodcastEntity] {
        // Get libraries
        let libraries = try await AudioBookshelfAPI.shared.getLibraries()

        // Find first podcast library
        guard let podcastLibrary = libraries.first(where: { $0.mediaType == "podcast" }) else {
            return []
        }

        // Fetch podcasts
        let podcasts = try await AudioBookshelfAPI.shared.getPodcasts(libraryId: podcastLibrary.id)

        // Convert to entities
        return podcasts.map { podcast in
            PodcastEntity(id: podcast.id, displayString: podcast.title)
        }
    }
}

// String search query support
extension PodcastQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [PodcastEntity] {
        let allPodcasts = try await fetchAllPodcasts()

        // Filter by title matching the search string
        return allPodcasts.filter { podcast in
            podcast.displayString.localizedCaseInsensitiveContains(string)
        }
    }
}
