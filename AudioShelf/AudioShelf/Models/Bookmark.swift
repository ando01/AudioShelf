//
//  Bookmark.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-12.
//

import Foundation

struct Bookmark: Codable, Identifiable {
    let id: String
    let episodeId: String
    let timestamp: Double  // Seconds into episode
    let note: String?      // Optional note/label
    let createdAt: Date

    init(id: String = UUID().uuidString, episodeId: String, timestamp: Double, note: String?) {
        self.id = id
        self.episodeId = episodeId
        self.timestamp = timestamp
        self.note = note
        self.createdAt = Date()
    }

    var formattedTimestamp: String {
        let totalSeconds = Int(timestamp)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
