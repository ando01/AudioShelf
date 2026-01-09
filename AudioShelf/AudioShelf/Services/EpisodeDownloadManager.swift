//
//  EpisodeDownloadManager.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-09.
//

import Foundation

@Observable
class EpisodeDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = EpisodeDownloadManager()

    private(set) var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private(set) var downloadProgress: [String: Double] = [:]
    private(set) var downloadedEpisodes: Set<String> = []
    private var episodeIdForTask: [Int: String] = [:]

    private let fileManager = FileManager.default
    private var downloadSession: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.isDiscretionary = false
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        loadDownloadedEpisodes()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("✅ Download finished downloading to: \(location)")
        guard let episodeId = episodeIdForTask[downloadTask.taskIdentifier] else {
            print("❌ No episode ID found for completed download task: \(downloadTask.taskIdentifier)")
            return
        }

        print("✅ Handling download completion for episode: \(episodeId)")
        DispatchQueue.main.async {
            self.handleDownloadCompletion(episodeId: episodeId, location: location)
        }
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

    private func getLocalFileURL(for episodeId: String) -> URL {
        return getDownloadsDirectory().appendingPathComponent("\(episodeId).mp3")
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
    }

    func deleteDownload(episodeId: String) {
        let localURL = getLocalFileURL(for: episodeId)

        do {
            if fileManager.fileExists(atPath: localURL.path) {
                try fileManager.removeItem(at: localURL)
                downloadedEpisodes.remove(episodeId)
                saveDownloadedEpisodes()
                print("Deleted download for episode: \(episodeId)")
            }
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
        let url = getLocalFileURL(for: episodeId)
        return fileManager.fileExists(atPath: url.path) ? url : nil
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

    func handleDownloadCompletion(episodeId: String, location: URL) {
        let destination = getLocalFileURL(for: episodeId)

        do {
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            // Move downloaded file to permanent location
            try fileManager.moveItem(at: location, to: destination)

            downloadedEpisodes.insert(episodeId)
            saveDownloadedEpisodes()

            // Clean up download tracking
            if let task = downloadTasks[episodeId] {
                episodeIdForTask.removeValue(forKey: task.taskIdentifier)
            }
            downloadTasks.removeValue(forKey: episodeId)
            downloadProgress.removeValue(forKey: episodeId)

            print("Download completed for episode: \(episodeId)")
        } catch {
            print("Failed to save download: \(error)")
        }
    }
}
