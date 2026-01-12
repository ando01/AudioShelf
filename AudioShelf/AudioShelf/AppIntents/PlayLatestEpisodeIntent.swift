//
//  PlayLatestEpisodeIntent.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-12.
//

import Foundation
import AppIntents

struct PlayLatestEpisodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Latest Episode"

    static var description = IntentDescription("Plays the latest episode of a podcast")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Podcast", requestValueDialog: IntentDialog("Which podcast?"))
    var podcast: PodcastEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Play latest episode") {
            \.$podcast
        }
    }

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
        guard !podcasts.isEmpty else {
            throw PlaybackError.noPodcastsFound
        }

        // Determine which podcast to use
        let targetPodcast: Podcast
        if let podcastParam = podcast {
            // User specified a podcast
            guard let found = podcasts.first(where: { $0.id == podcastParam.id }) else {
                throw PlaybackError.podcastNotFound
            }
            targetPodcast = found
        } else {
            // No podcast specified - use the most recently updated one
            guard let mostRecent = podcasts.first else {
                throw PlaybackError.noPodcastsFound
            }
            targetPodcast = mostRecent
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

enum PlaybackError: Error, LocalizedError {
    case notLoggedIn
    case noEpisodesFound
    case noLibraryFound
    case podcastNotFound
    case noPodcastsFound
    case serverURLNotAvailable
    case audioFileNotAvailable
    case notAuthenticated
    case invalidAudioURL

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "You need to be logged in to play episodes"
        case .noEpisodesFound:
            return "No episodes found for this podcast"
        case .noLibraryFound:
            return "No podcast library found"
        case .podcastNotFound:
            return "Podcast not found"
        case .noPodcastsFound:
            return "No podcasts found in your library"
        case .serverURLNotAvailable:
            return "Server URL not available"
        case .audioFileNotAvailable:
            return "Audio file not available"
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidAudioURL:
            return "Invalid audio URL"
        }
    }
}
