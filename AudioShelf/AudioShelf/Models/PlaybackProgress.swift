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
    let isFinished: Bool         // Manually marked as finished

    var percentComplete: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    var isCompleted: Bool {
        isFinished || percentComplete >= 0.95   // Consider 95%+ or manually marked as complete
    }

    var formattedProgress: String {
        if isFinished {
            return "Finished"
        }
        let percent = Int(percentComplete * 100)
        return "\(percent)%"
    }
}
