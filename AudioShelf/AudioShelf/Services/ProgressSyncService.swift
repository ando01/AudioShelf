//
//  ProgressSyncService.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-06.
//

import Foundation

/// Orchestrates progress sync between local storage and server
class ProgressSyncService {
    static let shared = ProgressSyncService()

    private let localService = PlaybackProgressService.shared
    private let api = AudioBookshelfAPI.shared
    private let syncQueue = DispatchQueue(label: "com.audioshelf.progresssync")

    // Pending sync queue for offline support
    private var pendingSyncs: [PendingSync] = []
    private let pendingSyncsKey = "pendingProgressSyncs"
    private let userDefaults = UserDefaults.standard

    // Debounce tracking
    private var lastServerSyncTime: [String: Date] = [:]
    private let minimumSyncInterval: TimeInterval = 30 // Seconds between server syncs

    // Track active sync tasks to prevent duplicates
    private var activeSyncTasks: Set<String> = []

    private init() {
        loadPendingSyncs()
        // Attempt to sync pending items on launch
        Task {
            await syncPendingItems()
        }
    }

    // MARK: - Public Interface

    /// Save progress locally and sync to server (debounced)
    func saveProgress(
        episodeId: String,
        libraryItemId: String,
        currentTime: Double,
        duration: Double,
        forceSyncNow: Bool = false
    ) {
        // Always save locally immediately
        localService.saveProgress(
            episodeId: episodeId,
            currentTime: currentTime,
            duration: duration
        )

        // Debounce server sync unless forced
        let shouldSync = forceSyncNow || shouldSyncToServer(episodeId: episodeId)
        print("🔄 [ProgressSync] saveProgress: episodeId=\(episodeId), currentTime=\(currentTime), forceSyncNow=\(forceSyncNow), willSync=\(shouldSync)")

        if shouldSync {
            Task {
                await syncToServer(
                    episodeId: episodeId,
                    libraryItemId: libraryItemId,
                    currentTime: currentTime,
                    duration: duration,
                    isFinished: false
                )
            }
        }
    }

    /// Mark episode as finished locally and sync to server
    func markAsFinished(
        episodeId: String,
        libraryItemId: String,
        duration: Double
    ) {
        localService.markAsFinished(episodeId: episodeId, duration: duration)

        Task {
            await syncToServer(
                episodeId: episodeId,
                libraryItemId: libraryItemId,
                currentTime: duration,
                duration: duration,
                isFinished: true
            )
        }
    }

    /// Fetch progress from server and merge with local
    func fetchAndMergeProgress(
        episodeId: String,
        libraryItemId: String
    ) async -> EpisodeProgress? {
        print("🔄 [ProgressSync] fetchAndMergeProgress called for episode: \(episodeId), libraryItem: \(libraryItemId)")

        // First get local progress
        let localProgress = localService.getProgress(episodeId: episodeId)
        if let local = localProgress {
            print("🔄 [ProgressSync] Local progress: currentTime=\(local.currentTime), percentComplete=\(local.percentComplete)")
        } else {
            print("🔄 [ProgressSync] No local progress found")
        }

        // Try to fetch server progress
        do {
            if let serverProgress = try await api.getProgress(
                libraryItemId: libraryItemId,
                episodeId: episodeId
            ) {
                print("🔄 [ProgressSync] Server progress: currentTime=\(serverProgress.currentTime), progress=\(serverProgress.progress)")
                return resolveConflict(
                    local: localProgress,
                    server: serverProgress,
                    episodeId: episodeId,
                    libraryItemId: libraryItemId
                )
            } else {
                print("🔄 [ProgressSync] No server progress found (404)")
            }
        } catch {
            print("🔄 [ProgressSync] Failed to fetch server progress: \(error)")
            // Fall through to return local
        }

        return localProgress
    }

    /// Sync all progress from server (call on app launch)
    func syncAllFromServer() async {
        print("🔄 [ProgressSync] syncAllFromServer called")
        do {
            let serverItems = try await api.getItemsInProgress()
            print("🔄 [ProgressSync] Got \(serverItems.count) items in progress from server")

            for serverProgress in serverItems {
                print("🔄 [ProgressSync] Server progress: episodeId=\(serverProgress.episodeId), currentTime=\(serverProgress.currentTime), progress=\(serverProgress.progress)")
                let localProgress = localService.getProgress(
                    episodeId: serverProgress.episodeId
                )
                if let local = localProgress {
                    print("🔄 [ProgressSync] Local progress: currentTime=\(local.currentTime)")
                } else {
                    print("🔄 [ProgressSync] No local progress for this episode")
                }

                _ = resolveConflict(
                    local: localProgress,
                    server: serverProgress,
                    episodeId: serverProgress.episodeId,
                    libraryItemId: serverProgress.libraryItemId
                )
            }

            // After syncing from server, push any pending local changes
            await syncPendingItems()
        } catch {
            print("🔄 [ProgressSync] Failed to sync progress from server: \(error)")
        }
    }

    /// Get progress (local only, for fast access)
    func getLocalProgress(episodeId: String) -> EpisodeProgress? {
        return localService.getProgress(episodeId: episodeId)
    }

    /// Clear progress locally and on server
    func clearProgress(episodeId: String, libraryItemId: String) {
        localService.clearProgress(episodeId: episodeId)
        // Note: Audiobookshelf API doesn't have a delete progress endpoint
        // Setting progress to 0 with isFinished=false effectively resets it
        Task {
            await syncToServer(
                episodeId: episodeId,
                libraryItemId: libraryItemId,
                currentTime: 0,
                duration: 0,
                isFinished: false
            )
        }
    }

    // MARK: - Private Methods

    private func shouldSyncToServer(episodeId: String) -> Bool {
        guard let lastSync = lastServerSyncTime[episodeId] else {
            return true
        }
        return Date().timeIntervalSince(lastSync) >= minimumSyncInterval
    }

    private func syncToServer(
        episodeId: String,
        libraryItemId: String,
        currentTime: Double,
        duration: Double,
        isFinished: Bool
    ) async {
        // Prevent duplicate syncs for same episode
        let syncKey = episodeId
        let alreadySyncing = syncQueue.sync {
            if activeSyncTasks.contains(syncKey) {
                return true
            }
            activeSyncTasks.insert(syncKey)
            return false
        }

        guard !alreadySyncing else { return }

        defer {
            syncQueue.sync {
                activeSyncTasks.remove(syncKey)
            }
        }

        do {
            print("🔄 [ProgressSync] Syncing to server: episodeId=\(episodeId), libraryItemId=\(libraryItemId), currentTime=\(currentTime), duration=\(duration)")
            try await api.updateProgress(
                libraryItemId: libraryItemId,
                episodeId: episodeId,
                currentTime: currentTime,
                duration: duration,
                isFinished: isFinished
            )

            lastServerSyncTime[episodeId] = Date()
            print("🔄 [ProgressSync] ✅ Successfully synced to server for episode: \(episodeId)")

        } catch {
            print("🔄 [ProgressSync] ❌ Failed to sync progress to server: \(error)")
            // Queue for later sync
            queuePendingSync(
                episodeId: episodeId,
                libraryItemId: libraryItemId,
                currentTime: currentTime,
                duration: duration,
                isFinished: isFinished
            )
        }
    }

    // MARK: - Conflict Resolution

    private func resolveConflict(
        local: EpisodeProgress?,
        server: ServerProgress,
        episodeId: String,
        libraryItemId: String
    ) -> EpisodeProgress {
        // Strategy: Use whichever has more progress (higher currentTime)
        // unless one is marked as finished

        let serverLastUpdate = server.lastUpdate.map {
            Date(timeIntervalSince1970: $0 / 1000)
        } ?? Date.distantPast

        // If server says finished, trust that
        if server.isFinished {
            localService.markAsFinished(
                episodeId: episodeId,
                duration: server.duration
            )
            return EpisodeProgress(
                episodeId: episodeId,
                currentTime: server.currentTime,
                duration: server.duration,
                lastPlayedDate: serverLastUpdate,
                isFinished: true
            )
        }

        // If we have local progress
        if let local = local {
            // If local is finished, keep local
            if local.isFinished {
                return local
            }

            // Use whichever has more progress
            if local.currentTime > server.currentTime {
                // Local is ahead - keep local and queue sync to server
                Task {
                    await syncToServer(
                        episodeId: episodeId,
                        libraryItemId: libraryItemId,
                        currentTime: local.currentTime,
                        duration: local.duration,
                        isFinished: local.isFinished
                    )
                }
                return local
            } else {
                // Server is ahead - update local
                localService.saveProgress(
                    episodeId: episodeId,
                    currentTime: server.currentTime,
                    duration: server.duration
                )
                return EpisodeProgress(
                    episodeId: episodeId,
                    currentTime: server.currentTime,
                    duration: server.duration,
                    lastPlayedDate: serverLastUpdate,
                    isFinished: false
                )
            }
        }

        // No local progress - use server
        localService.saveProgress(
            episodeId: episodeId,
            currentTime: server.currentTime,
            duration: server.duration
        )
        return EpisodeProgress(
            episodeId: episodeId,
            currentTime: server.currentTime,
            duration: server.duration,
            lastPlayedDate: serverLastUpdate,
            isFinished: server.isFinished
        )
    }

    // MARK: - Pending Sync Queue (Offline Support)

    private struct PendingSync: Codable {
        let episodeId: String
        let libraryItemId: String
        let currentTime: Double
        let duration: Double
        let isFinished: Bool
        let timestamp: Date
    }

    private func queuePendingSync(
        episodeId: String,
        libraryItemId: String,
        currentTime: Double,
        duration: Double,
        isFinished: Bool
    ) {
        syncQueue.sync {
            // Remove any existing pending sync for this episode
            pendingSyncs.removeAll { $0.episodeId == episodeId }

            // Add new pending sync
            pendingSyncs.append(PendingSync(
                episodeId: episodeId,
                libraryItemId: libraryItemId,
                currentTime: currentTime,
                duration: duration,
                isFinished: isFinished,
                timestamp: Date()
            ))

            savePendingSyncs()
        }
    }

    private func syncPendingItems() async {
        let itemsToSync = syncQueue.sync { pendingSyncs }

        for item in itemsToSync {
            do {
                try await api.updateProgress(
                    libraryItemId: item.libraryItemId,
                    episodeId: item.episodeId,
                    currentTime: item.currentTime,
                    duration: item.duration,
                    isFinished: item.isFinished
                )

                syncQueue.sync {
                    pendingSyncs.removeAll { $0.episodeId == item.episodeId }
                    savePendingSyncs()
                }

                print("Synced pending progress for: \(item.episodeId)")
            } catch {
                print("Still failed to sync: \(item.episodeId)")
                // Keep in queue for next attempt
            }
        }
    }

    private func loadPendingSyncs() {
        guard let data = userDefaults.data(forKey: pendingSyncsKey),
              let decoded = try? JSONDecoder().decode([PendingSync].self, from: data) else {
            return
        }
        pendingSyncs = decoded
    }

    private func savePendingSyncs() {
        if let encoded = try? JSONEncoder().encode(pendingSyncs) {
            userDefaults.set(encoded, forKey: pendingSyncsKey)
        }
    }
}
