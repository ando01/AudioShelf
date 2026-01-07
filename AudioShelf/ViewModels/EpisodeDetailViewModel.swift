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
    var audioPlayer = AudioPlayer()

    private let api = AudioBookshelfAPI.shared

    func loadEpisodes(for podcastId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            episodes = try await api.getEpisodes(podcastId: podcastId)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load episodes: \(error.localizedDescription)"
        }
    }

    func playEpisode(_ episode: Episode) {
        guard let serverURL = api.serverURL,
              let audioPath = episode.audioFile?.contentUrl else {
            errorMessage = "Audio file not available"
            return
        }

        let audioURLString = "\(serverURL)\(audioPath)"
        guard let audioURL = URL(string: audioURLString) else {
            errorMessage = "Invalid audio URL"
            return
        }

        selectedEpisode = episode
        audioPlayer.play(episode: episode, audioURL: audioURL)
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
