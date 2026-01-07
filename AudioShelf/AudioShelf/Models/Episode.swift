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

struct Episode: Identifiable {
    let id: String
    let title: String?
    let description: String?
    let publishedAt: Double?  // Timestamp in milliseconds
    let duration: Double?
    let audioFile: AudioFile?

    // Additional fields that might be present
    let enclosure: Enclosure?

    var publishedDate: Date? {
        guard let publishedAt = publishedAt else { return nil }
        // Convert from milliseconds to seconds
        return Date(timeIntervalSince1970: publishedAt / 1000.0)
    }

    var displayTitle: String {
        title ?? "Untitled Episode"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, publishedAt, duration, audioFile, enclosure
    }
}

extension Episode: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try? container.decode(String.self, forKey: .title)
        description = try? container.decode(String.self, forKey: .description)
        duration = try? container.decode(Double.self, forKey: .duration)
        audioFile = try? container.decode(AudioFile.self, forKey: .audioFile)
        enclosure = try? container.decode(Enclosure.self, forKey: .enclosure)

        // Handle publishedAt as either number or string
        if let timestamp = try? container.decode(Double.self, forKey: .publishedAt) {
            publishedAt = timestamp
        } else if let timestampInt = try? container.decode(Int.self, forKey: .publishedAt) {
            publishedAt = Double(timestampInt)
        } else if let dateString = try? container.decode(String.self, forKey: .publishedAt) {
            // Try parsing ISO 8601 string and convert to timestamp
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: dateString) {
                publishedAt = date.timeIntervalSince1970 * 1000.0
            } else {
                publishedAt = nil
            }
        } else {
            publishedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(audioFile, forKey: .audioFile)
        try container.encodeIfPresent(enclosure, forKey: .enclosure)
    }
}

extension Episode {
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

struct Enclosure: Codable {
    let url: String?
    let type: String?
}
