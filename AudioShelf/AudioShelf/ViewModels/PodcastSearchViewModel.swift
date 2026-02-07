//
//  PodcastSearchViewModel.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import Foundation
import Combine

@Observable
class PodcastSearchViewModel {
    var searchText = ""
    var searchResults: [PodcastSearchResult] = []
    var isSearching = false
    var errorMessage: String?

    var libraries: [Library] = []
    var libraryFolders: [LibraryFolder] = []
    var selectedLibrary: Library?
    var isAddingPodcast = false
    var addSuccess = false
    var addedPodcastTitle: String?
    var addError: String?

    private let api = AudioBookshelfAPI.shared
    private var searchTask: Task<Void, Never>?

    /// Search with 300ms debounce
    func search() {
        // Cancel previous search
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            searchResults = []
            return
        }

        searchTask = Task {
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                isSearching = true
                errorMessage = nil
            }

            do {
                let results = try await api.searchPodcasts(term: query)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    isSearching = false
                    if !Task.isCancelled {
                        errorMessage = "Search failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// Load libraries to determine where to add podcasts
    func loadLibraries() async {
        do {
            libraries = try await api.getLibraries()

            // Auto-select first podcast library
            selectedLibrary = libraries.first { $0.isPodcastLibrary }

            // Load folders for selected library
            if let library = selectedLibrary {
                await loadFolders(for: library)
            }
        } catch {
            errorMessage = "Failed to load libraries: \(error.localizedDescription)"
        }
    }

    /// Load folders for a library
    func loadFolders(for library: Library) async {
        do {
            libraryFolders = try await api.getLibraryFolders(libraryId: library.id)
        } catch {
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
        }
    }

    /// Add a podcast to the library
    func addPodcast(_ podcast: PodcastSearchResult) async {
        print("📥 Adding podcast: \(podcast.title)")
        print("📥 Feed URL: \(podcast.feedUrl)")

        guard let library = selectedLibrary else {
            print("📥 ❌ No library selected")
            await MainActor.run {
                addError = "No podcast library available. Please check your Audiobookshelf setup."
            }
            return
        }

        guard let folder = libraryFolders.first else {
            print("📥 ❌ No folders available for library: \(library.id)")
            await MainActor.run {
                addError = "No folder available in library. Please check your Audiobookshelf setup."
            }
            return
        }

        print("📥 Using library: \(library.id), folder: \(folder.id)")

        await MainActor.run {
            isAddingPodcast = true
            addSuccess = false
            addError = nil
        }

        do {
            try await api.addPodcast(
                libraryId: library.id,
                folderId: folder.id,
                podcastResult: podcast
            )

            print("📥 ✅ Podcast added successfully")

            await MainActor.run {
                isAddingPodcast = false
                addSuccess = true
                addedPodcastTitle = podcast.title
            }
        } catch {
            print("📥 ❌ Error: \(error)")
            await MainActor.run {
                isAddingPodcast = false
                addError = "Failed to add podcast: \(error.localizedDescription)"
            }
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        searchTask?.cancel()
    }

    func resetAddStatus() {
        addSuccess = false
        addedPodcastTitle = nil
    }
}
