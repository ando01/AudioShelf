//
//  PlaybackProgress.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-08.
//

import Foundation

struct EpisodeProgress: Codable {
    let episodeId: String
    let currentTime: Double      // Seconds into episode
    let duration: Double         // Total episode duration
    let lastPlayedDate: Date

    var percentComplete: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    var isCompleted: Bool {
        percentComplete >= 0.95   // Consider 95%+ as complete
    }

    var formattedProgress: String {
        let percent = Int(percentComplete * 100)
        return "\(percent)%"
    }
}
