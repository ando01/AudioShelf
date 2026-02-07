//
//  PodcastSearchResult.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import Foundation

struct PodcastSearchResult: Codable, Identifiable {
    let id: Int              // iTunes ID
    let artistId: Int?
    let title: String
    let artistName: String
    let description: String?
    let cover: String?       // Cover image URL
    let feedUrl: String
    let trackCount: Int
    let genres: [String]
    let explicit: Bool
}
