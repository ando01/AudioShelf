//
//  HomeViewModel.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import Foundation

@Observable
class HomeViewModel {
    var podcasts: [Podcast] = []
    var isLoading = false
    var errorMessage: String?
    var isOfflineMode = false

    private let api = AudioBookshelfAPI.shared
    private var selectedLibrary: Library?

    /// Top 10 podcasts by latest episode date for the carousel
    var carouselPodcasts: [Podcast] {
        Array(podcasts.prefix(10))
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let libraries = try await api.getLibraries()
            isOfflineMode = api.isOfflineMode

            // Find first podcast library
            guard let library = libraries.first(where: { $0.isPodcastLibrary }) else {
                isLoading = false
                errorMessage = "No podcast library found"
                return
            }

            selectedLibrary = library
            podcasts = try await api.getPodcasts(libraryId: library.id)
            isOfflineMode = api.isOfflineMode
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load podcasts: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        await loadData()
    }
}
