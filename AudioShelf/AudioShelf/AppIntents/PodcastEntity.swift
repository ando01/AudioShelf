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
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard AudioBookshelfAPI.shared.isLoggedIn else {
                    continuation.resume(returning: [])
                    return
                }

                do {
                    let allPodcasts = try await self.fetchAllPodcasts()
                    let filtered = allPodcasts.filter { identifiers.contains($0.id) }
                    continuation.resume(returning: filtered)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func suggestedEntities() async throws -> [PodcastEntity] {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard AudioBookshelfAPI.shared.isLoggedIn else {
                    continuation.resume(returning: [])
                    return
                }

                do {
                    let podcasts = try await self.fetchAllPodcasts()
                    continuation.resume(returning: podcasts)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func defaultResult() async -> PodcastEntity? {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                do {
                    let podcasts = try await self.fetchAllPodcasts()
                    continuation.resume(returning: podcasts.first)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func entities(matching string: String) async throws -> [PodcastEntity] {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard AudioBookshelfAPI.shared.isLoggedIn else {
                    continuation.resume(returning: [])
                    return
                }

                do {
                    let allPodcasts = try await self.fetchAllPodcasts()

                    // Filter by title matching the search string (case insensitive)
                    let matches = allPodcasts.filter { podcast in
                        podcast.displayString.localizedCaseInsensitiveContains(string)
                    }

                    continuation.resume(returning: matches)
                } catch {
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
