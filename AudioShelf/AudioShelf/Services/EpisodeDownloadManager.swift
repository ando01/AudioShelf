//
//  EpisodeDownloadManager.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-09.
//

import Foundation

#if os(iOS)
@Observable
class EpisodeDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = EpisodeDownloadManager()

    private(set) var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private(set) var downloadProgress: [String: Double] = [:]
    private(set) var downloadedEpisodes: Set<String> = []
    private var episodeIdForTask: [Int: String] = [:]
    /// Tracks the MIME type for each downloading episode to determine file extension
    private var mimeTypeForEpisode: [String: String] = [:]

    private let fileManager = FileManager.default
    private var downloadSession: URLSession!

    /// All supported file extensions for downloaded episodes
    private static let supportedExtensions = ["mp3", "m4a", "mp4", "m4v", "webm"]

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.isDiscretionary = false
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        loadDownloadedEpisodes()
    }

    // MARK: - File Extension Mapping

    /// Returns the appropriate file extension for a given MIME type
    private static func fileExtension(for mimeType: String?) -> String {
        guard let mimeType = mimeType?.lowercased() else { return "mp3" }
        switch mimeType {
        case "video/mp4": return "mp4"
        case "video/x-m4v": return "m4v"
        case "video/webm": return "webm"
        case "audio/mp4", "audio/x-m4a", "audio/aac": return "m4a"
        case "audio/mpeg", "audio/mp3": return "mp3"
        default:
            if mimeType.hasPrefix("video/") { return "mp4" }
            return "mp3"
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("✅ Download finished downloading to: \(location)")
        guard let episodeId = episodeIdForTask[downloadTask.taskIdentifier] else {
            print("❌ No episode ID found for completed download task: \(downloadTask.taskIdentifier)")
            return
        }

        let mimeType = mimeTypeForEpisode[episodeId]
        print("✅ Handling download completion for episode: \(episodeId)")
        // MUST move file synchronously before returning - temp file is deleted after this method returns
        handleDownloadCompletion(episodeId: episodeId, location: location, mimeType: mimeType)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let episodeId = episodeIdForTask[downloadTask.taskIdentifier] else {
            print("⚠️ No episode ID for download progress task: \(downloadTask.taskIdentifier)")
            return
        }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        print("📊 Download progress for \(episodeId): \(Int(progress * 100))% (\(totalBytesWritten)/\(totalBytesExpectedToWrite))")
        DispatchQueue.main.async {
            self.downloadProgress[episodeId] = progress
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let episodeId = episodeIdForTask[task.taskIdentifier] else {
            if let error = error {
                print("❌ Task completed with error but no episode ID: \(error)")
            }
            return
        }

        if let error = error {
            print("❌ Download failed for \(episodeId): \(error)")
            print("   Error domain: \(error._domain)")
            print("   Error code: \(error._code)")
            DispatchQueue.main.async {
                self.downloadTasks.removeValue(forKey: episodeId)
                self.downloadProgress.removeValue(forKey: episodeId)
                self.episodeIdForTask.removeValue(forKey: task.taskIdentifier)
                self.mimeTypeForEpisode.removeValue(forKey: episodeId)
            }
        } else {
            print("✅ Task completed successfully for: \(episodeId)")
        }
    }

    // MARK: - Download Directory

    private func getDownloadsDirectory() -> URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let downloadsDir = documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: downloadsDir.path) {
            try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }

        return downloadsDir
    }

    private func getLocalFileURL(for episodeId: String, mimeType: String? = nil) -> URL {
        let ext = Self.fileExtension(for: mimeType)
        return getDownloadsDirectory().appendingPathComponent("\(episodeId).\(ext)")
    }

    /// Finds the local file for an episode, checking all supported extensions
    private func findLocalFile(for episodeId: String) -> URL? {
        let dir = getDownloadsDirectory()
        for ext in Self.supportedExtensions {
            let url = dir.appendingPathComponent("\(episodeId).\(ext)")
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    // MARK: - Download Management

    func downloadEpisode(_ episode: Episode, audioURL: URL) {
        print("🔵 downloadEpisode called for: \(episode.displayTitle)")
        print("🔵 Episode ID: \(episode.id)")
        print("🔵 Audio URL: \(audioURL)")

        guard !isDownloaded(episodeId: episode.id) else {
            print("⚠️ Episode already downloaded: \(episode.id)")
            return
        }

        // Store the MIME type for determining file extension on completion
        mimeTypeForEpisode[episode.id] = episode.enclosure?.type

        print("🔵 Creating download task...")
        let task = downloadSession.downloadTask(with: audioURL)
        print("🔵 Task created with identifier: \(task.taskIdentifier)")

        downloadTasks[episode.id] = task
        downloadProgress[episode.id] = 0.0
        episodeIdForTask[task.taskIdentifier] = episode.id

        print("🔵 Resuming task...")
        task.resume()
        print("✅ Download task resumed for episode: \(episode.displayTitle)")
        print("🔵 Current download tasks count: \(downloadTasks.count)")
        print("🔵 Current episode ID mappings: \(episodeIdForTask)")
    }

    func cancelDownload(episodeId: String) {
        if let task = downloadTasks[episodeId] {
            episodeIdForTask.removeValue(forKey: task.taskIdentifier)
            task.cancel()
        }
        downloadTasks.removeValue(forKey: episodeId)
        downloadProgress.removeValue(forKey: episodeId)
        mimeTypeForEpisode.removeValue(forKey: episodeId)
    }

    func deleteDownload(episodeId: String) {
        // Check all supported extensions for the file
        guard let localURL = findLocalFile(for: episodeId) else {
            downloadedEpisodes.remove(episodeId)
            saveDownloadedEpisodes()
            return
        }

        do {
            try fileManager.removeItem(at: localURL)
            downloadedEpisodes.remove(episodeId)
            saveDownloadedEpisodes()
            print("Deleted download for episode: \(episodeId)")
        } catch {
            print("Failed to delete download: \(error)")
        }
    }

    // MARK: - Download Status

    func isDownloaded(episodeId: String) -> Bool {
        return downloadedEpisodes.contains(episodeId)
    }

    func isDownloading(episodeId: String) -> Bool {
        return downloadTasks[episodeId] != nil
    }

    func getDownloadProgress(episodeId: String) -> Double {
        return downloadProgress[episodeId] ?? 0.0
    }

    func getLocalURL(for episodeId: String) -> URL? {
        guard isDownloaded(episodeId: episodeId) else { return nil }
        return findLocalFile(for: episodeId)
    }

    // MARK: - Persistence

    private func loadDownloadedEpisodes() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "downloadedEpisodes"),
           let episodes = try? JSONDecoder().decode(Set<String>.self, from: data) {
            downloadedEpisodes = episodes
        }
    }

    private func saveDownloadedEpisodes() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(downloadedEpisodes) {
            defaults.set(data, forKey: "downloadedEpisodes")
        }
    }

    // MARK: - Download Completion

    func handleDownloadCompletion(episodeId: String, location: URL, mimeType: String? = nil) {
        // Ensure downloads directory exists
        let downloadsDir = getDownloadsDirectory()
        do {
            if !fileManager.fileExists(atPath: downloadsDir.path) {
                try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
                print("✅ Created downloads directory: \(downloadsDir.path)")
            }
        } catch {
            print("❌ Failed to create downloads directory: \(error)")
            return
        }

        let destination = getLocalFileURL(for: episodeId, mimeType: mimeType)
        print("📁 Moving file from: \(location.path)")
        print("📁 Moving file to: \(destination.path)")

        do {
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
                print("🗑 Removed existing file at destination")
            }

            // Move downloaded file to permanent location - MUST be done synchronously
            try fileManager.moveItem(at: location, to: destination)
            print("✅ Successfully moved file to permanent location")

            // Update state on main queue for UI updates
            DispatchQueue.main.async {
                self.downloadedEpisodes.insert(episodeId)
                self.saveDownloadedEpisodes()
                print("✅ Saved to downloaded episodes list")

                // Clean up download tracking
                if let task = self.downloadTasks[episodeId] {
                    self.episodeIdForTask.removeValue(forKey: task.taskIdentifier)
                }
                self.downloadTasks.removeValue(forKey: episodeId)
                self.downloadProgress.removeValue(forKey: episodeId)
                self.mimeTypeForEpisode.removeValue(forKey: episodeId)

                print("✅ Download completed for episode: \(episodeId)")
            }
        } catch {
            print("❌ Failed to save download: \(error)")
            print("   Location exists: \(fileManager.fileExists(atPath: location.path))")
            print("   Destination dir exists: \(fileManager.fileExists(atPath: downloadsDir.path))")
        }
    }
}

#else
// tvOS stub - downloads are not practical on tvOS due to limited local storage
@Observable
class EpisodeDownloadManager: NSObject {
    static let shared = EpisodeDownloadManager()

    private(set) var downloadTasks: [String: Any] = [:]
    private(set) var downloadProgress: [String: Double] = [:]
    private(set) var downloadedEpisodes: Set<String> = []

    private override init() {
        super.init()
    }

    func downloadEpisode(_ episode: Episode, audioURL: URL) {}
    func cancelDownload(episodeId: String) {}
    func deleteDownload(episodeId: String) {}
    func isDownloaded(episodeId: String) -> Bool { false }
    func isDownloading(episodeId: String) -> Bool { false }
    func getDownloadProgress(episodeId: String) -> Double { 0.0 }
    func getLocalURL(for episodeId: String) -> URL? { nil }
}
#endif
