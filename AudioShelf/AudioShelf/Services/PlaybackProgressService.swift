//
//  PlaybackProgressService.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-08.
//

import Foundation

class PlaybackProgressService {
    static let shared = PlaybackProgressService()

    private let userDefaults = UserDefaults.standard
    private let progressKey = "episodeProgress"

    private init() {}

    // Load all progress data
    private func loadAllProgress() -> [String: EpisodeProgress] {
        guard let data = userDefaults.data(forKey: progressKey),
              let decoded = try? JSONDecoder().decode([String: EpisodeProgress].self, from: data) else {
            return [:]
        }
        return decoded
    }

    // Save all progress data
    private func saveAllProgress(_ progress: [String: EpisodeProgress]) {
        if let encoded = try? JSONEncoder().encode(progress) {
            userDefaults.set(encoded, forKey: progressKey)
        }
    }

    // Save progress for a specific episode
    func saveProgress(episodeId: String, currentTime: Double, duration: Double) {
        guard currentTime > 0, duration > 0 else { return }

        var allProgress = loadAllProgress()
        // Preserve existing isFinished state if it exists
        let existingFinished = allProgress[episodeId]?.isFinished ?? false
        allProgress[episodeId] = EpisodeProgress(
            episodeId: episodeId,
            currentTime: currentTime,
            duration: duration,
            lastPlayedDate: Date(),
            isFinished: existingFinished
        )
        saveAllProgress(allProgress)
    }

    // Mark episode as finished
    func markAsFinished(episodeId: String, duration: Double) {
        var allProgress = loadAllProgress()
        allProgress[episodeId] = EpisodeProgress(
            episodeId: episodeId,
            currentTime: duration,  // Set to end
            duration: duration,
            lastPlayedDate: Date(),
            isFinished: true
        )
        saveAllProgress(allProgress)
    }

    // Get progress for a specific episode
    func getProgress(episodeId: String) -> EpisodeProgress? {
        return loadAllProgress()[episodeId]
    }

    // Clear progress for an episode (mark as unplayed)
    func clearProgress(episodeId: String) {
        var allProgress = loadAllProgress()
        allProgress.removeValue(forKey: episodeId)
        saveAllProgress(allProgress)
    }

    // Clear old progress (episodes not played in 90 days)
    func cleanupOldProgress() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        var allProgress = loadAllProgress()

        allProgress = allProgress.filter { _, progress in
            progress.lastPlayedDate > cutoffDate
        }

        saveAllProgress(allProgress)
    }
}
