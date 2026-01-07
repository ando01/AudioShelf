//
//  PodcastListViewModel.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

@Observable
class PodcastListViewModel {
    var podcasts: [Podcast] = []
    var libraries: [Library] = []
    var selectedLibrary: Library?
    var isLoading = false
    var errorMessage: String?

    private let api = AudioBookshelfAPI.shared

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
            podcasts = try await api.getPodcasts(libraryId: library.id)
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

    func logout() {
        api.logout()
        podcasts = []
        libraries = []
        selectedLibrary = nil
    }
}
