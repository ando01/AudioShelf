//
//  EpisodeDetailViewModel.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

@Observable
class EpisodeDetailViewModel {
    var episodes: [Episode] = []
    var selectedEpisode: Episode?
    var isLoading = false
    var errorMessage: String?
    var audioPlayer: AudioPlayer
    var podcast: Podcast
    var searchText: String = ""

    private let api = AudioBookshelfAPI.shared
    private var allEpisodes: [Episode] = []

    init(audioPlayer: AudioPlayer, podcast: Podcast) {
        self.audioPlayer = audioPlayer
        self.podcast = podcast
    }

    func loadEpisodes(for podcastId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            allEpisodes = try await api.getEpisodes(podcastId: podcastId)
            applyFiltering()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load episodes: \(error.localizedDescription)"
        }
    }

    func setSearchText(_ text: String) {
        searchText = text
        applyFiltering()
    }

    private func applyFiltering() {
        var filtered = allEpisodes

        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter { episode in
                // Search title
                let titleMatch = episode.displayTitle.lowercased().contains(searchLower)

                // Search description (strip HTML tags)
                let plainDescription = episode.description?.replacingOccurrences(
                    of: "<[^>]+>",
                    with: "",
                    options: .regularExpression
                ) ?? ""
                let descMatch = plainDescription.lowercased().contains(searchLower)

                return titleMatch || descMatch
            }
        }

        episodes = filtered
    }

    func playEpisode(_ episode: Episode) {
        // If this episode is already playing, toggle pause/resume
        if audioPlayer.currentEpisode?.id == episode.id {
            if audioPlayer.isPlaying {
                audioPlayer.pause()
            } else {
                audioPlayer.resume()
            }
            return
        }

        // Otherwise, start playing this episode
        guard let serverURL = api.serverURL else {
            errorMessage = "Server URL not available"
            return
        }

        // Get audio URL from enclosure (audioFile doesn't have contentUrl)
        let audioPath: String
        if let enclosureUrl = episode.enclosure?.url {
            audioPath = enclosureUrl
        } else {
            errorMessage = "Audio file not available"
            return
        }

        // If the path is already a full URL, use it directly
        let audioURLString: String
        if audioPath.hasPrefix("http://") || audioPath.hasPrefix("https://") {
            audioURLString = audioPath
        } else {
            // Otherwise, construct URL with server and add auth token
            guard let token = api.authToken else {
                errorMessage = "Not authenticated"
                return
            }
            audioURLString = "\(serverURL)\(audioPath)?token=\(token)"
        }

        guard let audioURL = URL(string: audioURLString) else {
            errorMessage = "Invalid audio URL"
            return
        }

        selectedEpisode = episode
        audioPlayer.play(episode: episode, audioURL: audioURL, podcast: podcast)
    }

    func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        } else if let episode = selectedEpisode {
            playEpisode(episode)
        }
    }

    func stopPlayback() {
        audioPlayer.stop()
        selectedEpisode = nil
    }
}
