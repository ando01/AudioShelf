//
//  PlayLatestFromDefaultIntent.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-13.
//

import Foundation
import AppIntents

struct PlayLatestFromDefaultIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Latest Episode"

    static var description = IntentDescription("Plays the latest episode from your most recent podcast")

    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Ensure user is logged in
        guard AudioBookshelfAPI.shared.isLoggedIn else {
            throw PlaybackError.notLoggedIn
        }

        // Get the full podcast list
        let libraries = try await AudioBookshelfAPI.shared.getLibraries()
        guard let podcastLibrary = libraries.first(where: { $0.mediaType == "podcast" }) else {
            throw PlaybackError.noLibraryFound
        }

        let podcasts = try await AudioBookshelfAPI.shared.getPodcasts(libraryId: podcastLibrary.id)

        // Use the most recently updated podcast (first in the sorted list)
        guard let targetPodcast = podcasts.first else {
            throw PlaybackError.noPodcastsFound
        }

        // Fetch episodes for the podcast
        let episodes = try await AudioBookshelfAPI.shared.getEpisodes(podcastId: targetPodcast.id)

        // Get the latest episode (first in the sorted list)
        guard let latestEpisode = episodes.first else {
            throw PlaybackError.noEpisodesFound
        }

        // Get audio URL for the episode
        let audioURL = try getAudioURL(for: latestEpisode)

        // Play the episode using AudioPlayer
        AudioPlayer.shared.play(episode: latestEpisode, audioURL: audioURL, podcast: targetPodcast)

        return .result(dialog: "Playing \(latestEpisode.displayTitle) from \(targetPodcast.title)")
    }

    private func getAudioURL(for episode: Episode) throws -> URL {
        // Check if episode is downloaded locally
        if let localURL = EpisodeDownloadManager.shared.getLocalURL(for: episode.id) {
            return localURL
        }

        // Otherwise, stream from server
        guard let serverURL = AudioBookshelfAPI.shared.serverURL else {
            throw PlaybackError.serverURLNotAvailable
        }

        // Get audio URL from enclosure
        guard let audioPath = episode.enclosure?.url else {
            throw PlaybackError.audioFileNotAvailable
        }

        // If the path is already a full URL, use it directly
        let audioURLString: String
        if audioPath.hasPrefix("http://") || audioPath.hasPrefix("https://") {
            audioURLString = audioPath
        } else {
            // Otherwise, construct URL with server and add auth token
            guard let token = AudioBookshelfAPI.shared.authToken else {
                throw PlaybackError.notAuthenticated
            }
            audioURLString = "\(serverURL)\(audioPath)?token=\(token)"
        }

        guard let audioURL = URL(string: audioURLString) else {
            throw PlaybackError.invalidAudioURL
        }

        return audioURL
    }
}
