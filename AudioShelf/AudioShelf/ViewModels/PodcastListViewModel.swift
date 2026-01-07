//
//  PodcastListViewModel.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

enum SortOption: String, CaseIterable {
    case latestEpisode = "Latest Episode"
    case title = "Title"
    case genre = "Genre"
}

@Observable
class PodcastListViewModel {
    var podcasts: [Podcast] = []
    var libraries: [Library] = []
    var selectedLibrary: Library?
    var isLoading = false
    var errorMessage: String?
    var sortOption: SortOption = .latestEpisode

    private let api = AudioBookshelfAPI.shared
    private var allPodcasts: [Podcast] = []  // Store unsorted podcasts

    func loadLibraries() async {
        isLoading = true
        errorMessage = nil

        do {
            libraries = try await api.getLibraries()

            // Auto-select first podcast library
            selectedLibrary = libraries.first { $0.isPodcastLibrary }

            if let library = selectedLibrary {
                await loadPodcasts(for: library)
            }

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load libraries: \(error.localizedDescription)"
        }
    }

    func loadPodcasts(for library: Library) async {
        isLoading = true
        errorMessage = nil
        selectedLibrary = library

        do {
            allPodcasts = try await api.getPodcasts(libraryId: library.id)
            applySorting()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load podcasts: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        if let library = selectedLibrary {
            await loadPodcasts(for: library)
        } else {
            await loadLibraries()
        }
    }

    func setSortOption(_ option: SortOption) {
        sortOption = option
        applySorting()
    }

    private func applySorting() {
        switch sortOption {
        case .latestEpisode:
            podcasts = allPodcasts.sorted { podcast1, podcast2 in
                if let date1 = podcast1.latestEpisodeDate,
                   let date2 = podcast2.latestEpisodeDate {
                    return date1 > date2
                }
                if podcast1.latestEpisodeDate != nil {
                    return true
                }
                if podcast2.latestEpisodeDate != nil {
                    return false
                }
                return podcast1.addedAt > podcast2.addedAt
            }
        case .title:
            podcasts = allPodcasts.sorted { $0.title.lowercased() < $1.title.lowercased() }
        case .genre:
            podcasts = allPodcasts.sorted { podcast1, podcast2 in
                let genre1 = podcast1.primaryGenre.lowercased()
                let genre2 = podcast2.primaryGenre.lowercased()
                if genre1 == genre2 {
                    return podcast1.title.lowercased() < podcast2.title.lowercased()
                }
                return genre1 < genre2
            }
        }
    }

    func logout() {
        api.logout()
        podcasts = []
        allPodcasts = []
        libraries = []
        selectedLibrary = nil
    }
}
