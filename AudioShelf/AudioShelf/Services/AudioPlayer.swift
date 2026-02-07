//
//  AudioPlayer.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
#if os(iOS)
import UIKit
#endif

@Observable
class AudioPlayer {
    static let shared = AudioPlayer()

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cachedArtwork: MPMediaItemArtwork?
    private let syncService = ProgressSyncService.shared
    private let metadataCache = AudioMetadataCache.shared
    private var lastSaveTime: Double = 0
    private var currentLibraryItemId: String?

    // Status observation for readiness-based seeking
    private var statusObservation: NSKeyValueObservation?
    private var pendingSeekTime: Double?

    // Timing diagnostics for playback startup
    private var playbackStartTime: Date?
    private var playerItemCreatedTime: Date?
    private var firstPlaybackTime: Date?
    private var hasLoggedFirstPlayback = false
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var playbackLikelyObservation: NSKeyValueObservation?

    var isPlaying = false
    var isBuffering = false  // Kept for compatibility but not actively used

    /// Read-only access to the AVPlayer for video rendering
    var avPlayer: AVPlayer? { player }

    /// Whether the currently playing episode is a video episode
    var isVideoEpisode: Bool {
        currentEpisode?.isVideo ?? false
    }

    // Mark currentTime as ObservationIgnored to prevent excessive view updates (updates every 0.5s)
    // Views that need real-time updates should use the timeUpdatePublisher instead
    @ObservationIgnored var currentTime: Double = 0

    // Publisher for time updates - views can subscribe to this for real-time time display
    @ObservationIgnored let timeUpdatePublisher = PassthroughSubject<Double, Never>()

    var duration: Double = 0
    var currentEpisode: Episode?
    var currentPodcast: Podcast?
    var playbackSpeed: Float = 1.0

    private init() {
        configureAudioSession()
        setupRemoteCommandCenter()
        setupAudioSessionNotifications()
        // Clean up old progress and expired metadata on launch
        PlaybackProgressService.shared.cleanupOldProgress()
        metadataCache.cleanupExpiredEntries()
    }

    private func setupAudioSessionNotifications() {
        #if os(iOS)
        // Handle audio session interruptions (calls, alarms, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                // Interruption began (phone call, etc.) - pause playback
                self.pause()
            case .ended:
                // Interruption ended
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        // Resume playback if appropriate
                        self.resume()
                    }
                }
            @unknown default:
                break
            }
        }
        #endif
    }

    func play(episode: Episode, audioURL: URL, podcast: Podcast? = nil) {
        // If playing a different episode, create new player
        if currentEpisode?.id != episode.id {
            stop()

            // Start timing diagnostics
            playbackStartTime = Date()
            hasLoggedFirstPlayback = false
            print("⏱️ [TIMING] ========== PLAYBACK START ==========")
            print("⏱️ [TIMING] Episode: \(episode.displayTitle)")
            print("⏱️ [TIMING] URL: \(audioURL.absoluteString.prefix(100))...")
            print("⏱️ [TIMING] T+0.000s: play() called")

            currentEpisode = episode
            currentPodcast = podcast
            currentLibraryItemId = podcast?.id
            cachedArtwork = nil  // Clear cached artwork for new episode
            configureAudioSession(forVideo: episode.isVideo)

            // Set duration from multiple sources in order of preference
            // 1. Cached metadata (fastest)
            // 2. Episode metadata from API
            // 3. AVPlayer will load it (slowest, fallback)
            if let cachedDuration = metadataCache.getDuration(episodeId: episode.id), cachedDuration > 0 {
                self.duration = cachedDuration
                print("✅ Using cached duration: \(cachedDuration) seconds")
            } else if let episodeDuration = episode.durationSeconds, episodeDuration > 0 {
                self.duration = episodeDuration
                // Cache it for next time
                metadataCache.cacheDuration(episodeId: episode.id, duration: episodeDuration)
                print("✅ Using episode duration from metadata: \(episodeDuration) seconds")
            } else {
                print("⚠️ Episode duration unknown, waiting for AVPlayer...")
            }

            // Check for saved progress - store for seeking when ready
            // First check local progress for fast startup
            if let savedProgress = syncService.getLocalProgress(episodeId: episode.id),
               savedProgress.currentTime > 5.0,
               savedProgress.percentComplete < 0.95 {
                pendingSeekTime = savedProgress.currentTime
                print("📍 Will resume from \(savedProgress.currentTime) seconds when ready")
            } else {
                pendingSeekTime = nil
            }

            // Fetch server progress in background and update if needed
            if let libraryItemId = podcast?.id {
                Task {
                    if let serverProgress = await syncService.fetchAndMergeProgress(
                        episodeId: episode.id,
                        libraryItemId: libraryItemId
                    ),
                       serverProgress.currentTime > 5.0,
                       serverProgress.percentComplete < 0.95,
                       serverProgress.currentTime > (self.pendingSeekTime ?? 0) {
                        await MainActor.run {
                            // Check if we should seek
                            let shouldSeek = serverProgress.currentTime > self.currentTime + 5.0

                            if self.player?.currentItem?.status == .readyToPlay && shouldSeek {
                                // Player is already ready - seek directly
                                print("📍 Seeking to server progress: \(serverProgress.currentTime) seconds")
                                self.seek(to: serverProgress.currentTime)
                            } else if shouldSeek {
                                // Player not ready yet - update pending seek time
                                self.pendingSeekTime = serverProgress.currentTime
                                print("📍 Updated resume position from server: \(serverProgress.currentTime) seconds")
                            }
                        }
                    }
                }
            }

            // Create player item with optimized buffering
            logTiming("Creating AVPlayerItem")
            let playerItem = createOptimizedPlayerItem(url: audioURL)
            playerItemCreatedTime = Date()
            logTiming("AVPlayerItem created")

            player = AVPlayer(playerItem: playerItem)
            logTiming("AVPlayer initialized")

            // Configure player for fast startup
            player?.automaticallyWaitsToMinimizeStalling = false

            // Set up status observer for readiness-based seeking
            setupStatusObserver(for: playerItem)
            setupBufferObservers(for: playerItem)
            observeDuration()

            // Observe time updates
            let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                let previousTime = self.currentTime
                self.currentTime = time.seconds

                // Publish time update for views that need real-time updates
                self.timeUpdatePublisher.send(self.currentTime)

                // Detect first actual playback (time started moving)
                if self.firstPlaybackTime == nil && self.currentTime > 0.1 && previousTime < 0.1 {
                    self.firstPlaybackTime = Date()
                    self.logTiming("🎵 FIRST AUDIO PLAYBACK DETECTED")
                }

                self.updateNowPlayingInfo()

                // Auto-save every 10 seconds
                if self.currentTime - self.lastSaveTime >= 10.0,
                   let episode = self.currentEpisode,
                   let libraryItemId = self.currentLibraryItemId {
                    self.syncService.saveProgress(
                        episodeId: episode.id,
                        libraryItemId: libraryItemId,
                        currentTime: self.currentTime,
                        duration: self.duration,
                        forceSyncNow: false
                    )
                    self.lastSaveTime = self.currentTime
                }
            }

            // Load artwork asynchronously once for this episode
            Task {
                cachedArtwork = await loadArtwork()
                updateNowPlayingInfo()
            }
        }

        logTiming("Calling player.play()")
        player?.play()
        player?.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
        logTiming("play() method complete, waiting for buffering...")
    }

    // MARK: - Timing Diagnostics

    private func logTiming(_ event: String) {
        guard let startTime = playbackStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        print(String(format: "⏱️ [TIMING] T+%.3fs: %@", elapsed, event))
    }

    private func setupBufferObservers(for playerItem: AVPlayerItem) {
        // Clean up previous observers
        bufferEmptyObservation?.invalidate()
        playbackLikelyObservation?.invalidate()

        // Observe buffer empty state
        bufferEmptyObservation = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new, .old]) { [weak self] item, change in
            DispatchQueue.main.async {
                if let isEmpty = change.newValue {
                    self?.logTiming("Buffer empty: \(isEmpty)")
                }
            }
        }

        // Observe playback likely to keep up
        playbackLikelyObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .old]) { [weak self] item, change in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let isLikely = change.newValue, isLikely {
                    self.logTiming("Playback likely to keep up: YES")
                    if !self.hasLoggedFirstPlayback {
                        self.hasLoggedFirstPlayback = true
                        self.logTiming("✅ READY FOR SMOOTH PLAYBACK")
                        self.printTimingSummary()
                    }
                }
            }
        }
    }

    private func printTimingSummary() {
        guard let startTime = playbackStartTime else { return }
        let totalTime = Date().timeIntervalSince(startTime)

        print("⏱️ [TIMING] ========== SUMMARY ==========")
        print(String(format: "⏱️ [TIMING] Total startup time: %.3fs", totalTime))

        if let itemCreated = playerItemCreatedTime {
            let itemCreateTime = itemCreated.timeIntervalSince(startTime)
            print(String(format: "⏱️ [TIMING]   - PlayerItem creation: %.3fs", itemCreateTime))
        }

        if totalTime > 2.0 {
            print("⏱️ [TIMING] ⚠️ SLOW STARTUP DETECTED (>2s)")
        } else if totalTime > 1.0 {
            print("⏱️ [TIMING] ⚡ Moderate startup (1-2s)")
        } else {
            print("⏱️ [TIMING] 🚀 Fast startup (<1s)")
        }
        print("⏱️ [TIMING] ==============================")
    }

    /// Creates an AVPlayerItem with optimized buffering configuration
    private func createOptimizedPlayerItem(url: URL) -> AVPlayerItem {
        // Create player item directly from URL
        // The URL already contains authentication token as query parameter
        let playerItem = AVPlayerItem(url: url)

        // Configure buffering for fast startup
        // 2 seconds is minimal buffer - start playback ASAP, buffer more while playing
        playerItem.preferredForwardBufferDuration = 2

        return playerItem
    }

    /// Sets up observer for player item status to handle pending seeks
    private func setupStatusObserver(for playerItem: AVPlayerItem) {
        // Clean up previous observer
        statusObservation?.invalidate()

        // Observe player item status for readiness (for pending seek)
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.handlePlayerItemStatusChange(item)
            }
        }
    }

    /// Handles player item status changes - performs pending seek when ready
    private func handlePlayerItemStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            logTiming("AVPlayerItem status: readyToPlay")

            // Log buffer state
            let loadedRanges = item.loadedTimeRanges
            if let firstRange = loadedRanges.first?.timeRangeValue {
                let bufferedSeconds = CMTimeGetSeconds(firstRange.duration)
                logTiming(String(format: "Buffered: %.1fs", bufferedSeconds))
            }

            // Perform pending seek now that player is ready
            if let seekTime = pendingSeekTime {
                logTiming("Starting seek to \(seekTime) seconds")
                seek(to: seekTime)
                pendingSeekTime = nil
                logTiming("Seek command sent")
            }

            // Cache duration if we got it from AVPlayer
            if let episode = currentEpisode {
                let itemDuration = item.duration.seconds
                if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                    metadataCache.cacheDuration(episodeId: episode.id, duration: itemDuration)
                    logTiming("Duration from AVPlayer: \(itemDuration)s")
                }
            }

        case .failed:
            logTiming("❌ AVPlayerItem FAILED")
            print("❌ Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")

        case .unknown:
            break

        @unknown default:
            break
        }
    }

    func pause() {
        // Get actual player time and save progress on pause
        let actualCurrentTime: Double
        if let playerTime = player?.currentTime(), playerTime.isValid && !playerTime.isIndefinite {
            actualCurrentTime = playerTime.seconds
        } else {
            actualCurrentTime = currentTime
        }

        // Save and force sync progress when pausing
        if let episode = currentEpisode,
           let libraryItemId = currentLibraryItemId,
           actualCurrentTime > 0 {
            syncService.saveProgress(
                episodeId: episode.id,
                libraryItemId: libraryItemId,
                currentTime: actualCurrentTime,
                duration: duration,
                forceSyncNow: true
            )
            print("Paused and saved progress: \(actualCurrentTime)s for episode \(episode.id)")
        }

        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        player?.play()
        player?.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingInfo()
    }

    func stop() {
        // Get the actual current time from the player (more accurate than cached currentTime)
        let actualCurrentTime: Double
        if let playerTime = player?.currentTime(), playerTime.isValid && !playerTime.isIndefinite {
            actualCurrentTime = playerTime.seconds
        } else {
            actualCurrentTime = currentTime
        }

        // Save progress before clearing - force sync to server
        if let episode = currentEpisode,
           let libraryItemId = currentLibraryItemId,
           actualCurrentTime > 0 {
            syncService.saveProgress(
                episodeId: episode.id,
                libraryItemId: libraryItemId,
                currentTime: actualCurrentTime,
                duration: duration,
                forceSyncNow: true
            )
            print("Saved progress: \(actualCurrentTime)s for episode \(episode.id)")
        }

        player?.pause()

        // Clean up time observer
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }

        // Clean up status observer
        statusObservation?.invalidate()
        statusObservation = nil

        // Clean up buffer observers
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        playbackLikelyObservation?.invalidate()
        playbackLikelyObservation = nil

        // Reset timing diagnostics
        playbackStartTime = nil
        playerItemCreatedTime = nil
        firstPlaybackTime = nil
        hasLoggedFirstPlayback = false

        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentEpisode = nil
        currentPodcast = nil
        currentLibraryItemId = nil
        cachedArtwork = nil
        pendingSeekTime = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to time: Double) {
        print("DEBUG SEEK: Attempting to seek to \(time) seconds")
        print("  - Current time: \(currentTime)")
        print("  - Duration: \(duration)")

        guard time >= 0 && !time.isNaN && !time.isInfinite else {
            print("  - ERROR: Invalid seek time!")
            return
        }

        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // Seek with no tolerance for accurate positioning
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        // Don't manually set currentTime - let the time observer update it naturally

        print("  - Seek command sent")
    }

    private func observeDuration() {
        guard let currentItem = player?.currentItem else { return }

        // Observe duration changes (only update if we don't already have a good duration)
        Task { @MainActor in
            for await _ in currentItem.publisher(for: \.status).values {
                if currentItem.status == .readyToPlay {
                    let itemDuration = currentItem.duration.seconds
                    if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                        // Only update if we don't have a duration yet
                        if self.duration <= 0 {
                            self.duration = itemDuration
                            print("Duration loaded from AVPlayer: \(itemDuration) seconds")
                        }
                    }
                }
            }
        }

        // Also observe duration directly in case it becomes available later
        Task { @MainActor in
            for await _ in currentItem.publisher(for: \.duration).values {
                let itemDuration = currentItem.duration.seconds
                if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                    // Only update if we don't have a duration yet
                    if self.duration <= 0 {
                        self.duration = itemDuration
                        print("Duration updated from AVPlayer: \(itemDuration) seconds")
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
    }

    // MARK: - Background Audio & Lock Screen Support

    private func configureAudioSession(forVideo: Bool = false) {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            let mode: AVAudioSession.Mode = forVideo ? .moviePlayback : .spokenAudio
            try audioSession.setCategory(.playback, mode: mode)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        #endif
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.currentEpisode != nil {
                self.resume()
            }
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        // Skip forward command (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            let newTime = self.currentTime + 30
            let seekTime = self.duration > 0 ? min(self.duration, newTime) : newTime
            self.seek(to: seekTime)
            return .success
        }

        // Skip backward command (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.seek(to: max(0, self.currentTime - 15))
            return .success
        }

        // Also map next/previous track to skip forward/backward for AirPods
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            let newTime = self.currentTime + 30
            let seekTime = self.duration > 0 ? min(self.duration, newTime) : newTime
            self.seek(to: seekTime)
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.seek(to: max(0, self.currentTime - 15))
            return .success
        }

        // Change playback position command (for scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: episode.displayTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0
        ]

        // Add podcast title as album/artist
        if let podcast = currentPodcast {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = podcast.title
            nowPlayingInfo[MPMediaItemPropertyArtist] = podcast.author
        }

        // Add cached artwork if available
        if let artwork = cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    #if os(iOS)
    private func loadArtwork() async -> MPMediaItemArtwork? {
        // First try to get podcast cover art
        if let podcast = currentPodcast,
           let coverURL = AudioBookshelfAPI.shared.getCoverImageURL(for: podcast) {
            if let image = await downloadImage(from: coverURL) {
                return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }

        // Fall back to app icon
        if let appIcon = getAppIcon() {
            return MPMediaItemArtwork(boundsSize: appIcon.size) { _ in appIcon }
        }

        return nil
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("Failed to download cover art: \(error)")
            return nil
        }
    }

    private func getAppIcon() -> UIImage? {
        // Try to get the app icon from the bundle
        // Method 1: Check if the icon files exist in the bundle root
        if let iconPath = Bundle.main.path(forResource: "AppIcon60x60@3x", ofType: "png"),
           let icon = UIImage(contentsOfFile: iconPath) {
            return icon
        }

        // Method 2: Try to access icons directory
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let iconName = iconFiles.last,
           let icon = UIImage(named: iconName) {
            return icon
        }

        // Method 3: Create a simple placeholder with app color
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Blue background (AudioShelf theme color)
            UIColor(red: 0, green: 0.48, blue: 1.0, alpha: 1.0).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Add "AS" text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 200, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]

            let text = "AS"
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
        }
    }
    #else
    private func loadArtwork() async -> MPMediaItemArtwork? {
        return nil
    }
    #endif
}
