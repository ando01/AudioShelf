//
//  Episode.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

struct EpisodesResponse: Codable {
    let episodes: [Episode]
}

struct Episode: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let publishedAt: String?  // ISO 8601 date string
    let duration: Double?
    let audioFile: AudioFile?

    var publishedDate: Date? {
        guard let publishedAt = publishedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: publishedAt)
    }

    var formattedPublishedDate: String {
        guard let date = publishedDate else { return "Unknown date" }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date, to: now)

        // Use relative date for recent episodes (within 7 days)
        if let days = components.day, days < 7 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Published: \(formatter.localizedString(for: date, relativeTo: now))"
        } else {
            // Use absolute date for older episodes
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Published: \(formatter.string(from: date))"
        }
    }

    var formattedDuration: String {
        guard let duration = duration else { return "" }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

struct AudioFile: Codable {
    let contentUrl: String?
}
