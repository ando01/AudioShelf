//
//  AudioClipService.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-28.
//

import AVFoundation
import Foundation
import UIKit

/// Service for creating and sharing audio clips from podcast episodes
class AudioClipService {
    static let shared = AudioClipService()

    private let downloadManager = EpisodeDownloadManager.shared
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Clip Creation

    /// Creates an audio clip from the specified time range
    /// - Parameters:
    ///   - episodeId: The episode ID
    ///   - audioURL: The source audio URL (can be remote or local)
    ///   - startTime: Start time in seconds
    ///   - endTime: End time in seconds
    ///   - completion: Callback with the result (URL to clip file or error)
    func createClip(
        episodeId: String,
        audioURL: URL,
        startTime: Double,
        endTime: Double,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Validate time range
        guard startTime < endTime else {
            completion(.failure(ClipError.invalidTimeRange))
            return
        }

        // Check if we have a local download first (faster and more reliable)
        let sourceURL: URL
        if let localURL = downloadManager.getLocalURL(for: episodeId) {
            sourceURL = localURL
            print("AudioClipService: Using local file for clip")
        } else {
            sourceURL = audioURL
            print("AudioClipService: Using remote URL for clip")
        }

        // Create the clip asynchronously
        Task {
            do {
                let clipURL = try await exportClip(
                    from: sourceURL,
                    startTime: startTime,
                    endTime: endTime,
                    episodeId: episodeId
                )
                await MainActor.run {
                    completion(.success(clipURL))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Export a clip from the audio source
    private func exportClip(
        from sourceURL: URL,
        startTime: Double,
        endTime: Double,
        episodeId: String
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        // Wait for the asset to load
        try await asset.load(.duration, .tracks)

        // Verify asset has audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw ClipError.noAudioTrack
        }

        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ClipError.exportSessionCreationFailed
        }

        // Set time range
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 1000)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 1000)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
        exportSession.timeRange = timeRange

        // Create output URL
        let clipFileName = "clip_\(episodeId.prefix(8))_\(Int(startTime))-\(Int(endTime)).m4a"
        let outputURL = getClipsDirectory().appendingPathComponent(clipFileName)

        // Remove existing file if present
        try? fileManager.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        // Export
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            print("AudioClipService: Clip exported successfully to \(outputURL)")
            return outputURL
        case .failed:
            throw exportSession.error ?? ClipError.exportFailed
        case .cancelled:
            throw ClipError.exportCancelled
        default:
            throw ClipError.exportFailed
        }
    }

    // MARK: - Sharing

    /// Present share sheet for a clip
    /// - Parameters:
    ///   - clipURL: URL to the clip file
    ///   - episodeTitle: Title of the episode for the share message
    ///   - podcastTitle: Title of the podcast
    ///   - startTime: Start time of the clip
    ///   - endTime: End time of the clip
    ///   - from: View controller to present from
    ///   - completion: Called when user completes or cancels sharing
    func shareClip(
        clipURL: URL,
        episodeTitle: String,
        podcastTitle: String,
        startTime: Double,
        endTime: Double,
        from viewController: UIViewController,
        completion: @escaping (Bool) -> Void
    ) {
        let clipDuration = Int(endTime - startTime)
        let message = "Check out this \(clipDuration)s clip from \"\(episodeTitle)\" - \(podcastTitle)"

        let activityItems: [Any] = [message, clipURL]

        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        // Exclude some activities that don't make sense for audio files
        activityVC.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks
        ]

        // Completion handler to know when sharing is done
        activityVC.completionWithItemsHandler = { activityType, completed, _, _ in
            completion(completed)
        }

        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
        }

        viewController.present(activityVC, animated: true)
    }

    // MARK: - Helpers

    private func getClipsDirectory() -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let clipsURL = documentsURL.appendingPathComponent("Clips")

        // Create directory if needed
        if !fileManager.fileExists(atPath: clipsURL.path) {
            try? fileManager.createDirectory(at: clipsURL, withIntermediateDirectories: true)
        }

        return clipsURL
    }

    func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    /// Clean up old clips (older than 7 days)
    func cleanupOldClips() {
        let clipsDir = getClipsDirectory()
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago

        guard let files = try? fileManager.contentsOfDirectory(
            at: clipsDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for fileURL in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < cutoffDate {
                try? fileManager.removeItem(at: fileURL)
                print("AudioClipService: Cleaned up old clip \(fileURL.lastPathComponent)")
            }
        }
    }

    // MARK: - Errors

    enum ClipError: LocalizedError {
        case invalidTimeRange
        case noAudioTrack
        case exportSessionCreationFailed
        case exportFailed
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case .invalidTimeRange:
                return "Invalid time range. Start time must be before end time."
            case .noAudioTrack:
                return "No audio track found in the episode."
            case .exportSessionCreationFailed:
                return "Failed to create export session."
            case .exportFailed:
                return "Failed to export clip."
            case .exportCancelled:
                return "Export was cancelled."
            }
        }
    }
}
