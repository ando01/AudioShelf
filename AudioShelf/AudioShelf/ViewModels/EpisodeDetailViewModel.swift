//
//  EpisodeDetailViewModel.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation
import Combine

@Observable
class EpisodeDetailViewModel {
    var episodes: [Episode] = []
    var selectedEpisode: Episode?
    var isLoading = false
    var errorMessage: String?
    var audioPlayer: AudioPlayer
    var podcast: Podcast
    var searchText: String = ""
    var episodeProgress: [String: EpisodeProgress] = [:]

    private let api = AudioBookshelfAPI.shared
    private var allEpisodes: [Episode] = []
    private let progressService = PlaybackProgressService.shared
    private var progressRefreshTimer: Timer?

    init(audioPlayer: AudioPlayer, podcast: Podcast) {
        self.audioPlayer = audioPlayer
        self.podcast = podcast
        startProgressRefreshTimer()
    }

    deinit {
        stopProgressRefreshTimer()
    }

    private func startProgressRefreshTimer() {
        // Refresh progress every 5 seconds while viewing episodes
        progressRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshProgressIfNeeded()
        }
    }

    private func stopProgressRefreshTimer() {
        progressRefreshTimer?.invalidate()
        progressRefreshTimer = nil
    }

    private func refreshProgressIfNeeded() {
        // Only refresh if we're currently playing an episode from this podcast
        guard let currentEpisode = audioPlayer.currentEpisode,
              allEpisodes.contains(where: { $0.id == currentEpisode.id }) else {
            return
        }

        // Update the progress for the currently playing episode
        if let updatedProgress = progressService.getProgress(episodeId: currentEpisode.id) {
            episodeProgress[currentEpisode.id] = updatedProgress
        }
    }

    func loadEpisodes(for podcastId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            allEpisodes = try await api.getEpisodes(podcastId: podcastId)
            applyFiltering()
            loadProgress()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load episodes: \(error.localizedDescription)"
        }
    }

    func loadProgress() {
        // Load progress for all episodes
        episodeProgress.removeAll()
        for episode in allEpisodes {
            if let progress = progressService.getProgress(episodeId: episode.id) {
                episodeProgress[episode.id] = progress
            }
        }
    }

    func refreshProgress() {
        // Refresh progress from the service (useful after playback)
        loadProgress()
    }

    func getProgress(for episode: Episode) -> EpisodeProgress? {
        return episodeProgress[episode.id]
    }

    func clearProgress(for episode: Episode) {
        progressService.clearProgress(episodeId: episode.id)
        episodeProgress.removeValue(forKey: episode.id)
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
