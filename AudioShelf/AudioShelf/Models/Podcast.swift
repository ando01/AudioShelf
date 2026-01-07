//
//  Podcast.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

struct PodcastsResponse: Codable {
    let results: [Podcast]
}

struct Podcast: Codable, Identifiable {
    let id: String
    let media: PodcastMedia
    let mediaType: String
    let addedAt: Int64

    var coverImageURL: String? {
        media.metadata.imageUrl
    }

    var title: String {
        media.metadata.title ?? "Unknown Podcast"
    }

    var author: String {
        media.metadata.author ?? "Unknown Author"
    }

    // Get the most recent episode's published date for sorting
    var latestEpisodeDate: Date? {
        guard let episodes = media.episodes else { return nil }
        return episodes.compactMap { $0.publishedDate }.max()
    }
}

struct PodcastMedia: Codable {
    let metadata: PodcastMetadata
    let episodes: [Episode]?
}

struct PodcastMetadata: Codable {
    let title: String?
    let author: String?
    let description: String?
    let imageUrl: String?
}
