//
//  Episode.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

enum EpisodeMediaType {
    case audio
    case video

    var iconName: String {
        switch self {
        case .audio: return "waveform"
        case .video: return "video.fill"
        }
    }

    var label: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }
}

struct EpisodesResponse: Codable {
    let episodes: [Episode]
}

struct Episode: Identifiable {
    let id: String
    let title: String?
    let description: String?
    let publishedAt: Double?  // Timestamp in milliseconds
    let duration: Double?  // Top-level duration (usually nil for podcasts)
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

    // Get duration from audioFile if top-level duration is not available
    var durationSeconds: Double? {
        if let duration = duration, duration > 0 {
            return duration
        }
        return audioFile?.durationSeconds
    }

    /// Whether this episode contains video content based on the enclosure MIME type
    var isVideo: Bool {
        guard let type = enclosure?.type?.lowercased() else { return false }
        return type.hasPrefix("video/")
    }

    /// The media type of this episode
    var mediaType: EpisodeMediaType {
        isVideo ? .video : .audio
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

        // Always show actual date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Published: \(formatter.string(from: date))"
    }

    var formattedDuration: String {
        guard let duration = durationSeconds else { return "" }
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
    let duration: Double?  // Duration in seconds

    var durationSeconds: Double? {
        return duration
    }

    enum CodingKeys: String, CodingKey {
        case duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode duration as Double first (most common), then as String
        if let durationDouble = try? container.decode(Double.self, forKey: .duration) {
            duration = durationDouble
        } else if let durationString = try? container.decode(String.self, forKey: .duration),
                  let durationDouble = Double(durationString) {
            duration = durationDouble
        } else {
            duration = nil
        }
    }
}

struct Enclosure: Codable {
    let url: String?
    let type: String?
}
