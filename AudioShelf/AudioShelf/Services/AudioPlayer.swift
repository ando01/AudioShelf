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
import UIKit

@Observable
class AudioPlayer {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cachedArtwork: MPMediaItemArtwork?

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var currentEpisode: Episode?
    var currentPodcast: Podcast?
    var playbackSpeed: Float = 1.0

    init() {
        configureAudioSession()
        setupRemoteCommandCenter()
    }

    func play(episode: Episode, audioURL: URL, podcast: Podcast? = nil) {
        // If playing a different episode, create new player
        if currentEpisode?.id != episode.id {
            stop()
            currentEpisode = episode
            currentPodcast = podcast
            cachedArtwork = nil  // Clear cached artwork for new episode

            // Debug: Check what duration we have
            print("DEBUG: Episode title: \(episode.displayTitle)")
            print("DEBUG: Episode.durationSeconds value: \(episode.durationSeconds?.description ?? "nil")")
            print("DEBUG: Episode.formattedDuration: \(episode.formattedDuration)")

            // Set duration from episode metadata immediately (more reliable than AVPlayer)
            if let episodeDuration = episode.durationSeconds, episodeDuration > 0 {
                self.duration = episodeDuration
                print("✅ Using episode duration from metadata: \(episodeDuration) seconds")
            } else {
                print("⚠️ Episode duration is nil or 0, waiting for AVPlayer...")
            }

            let playerItem = AVPlayerItem(url: audioURL)
            player = AVPlayer(playerItem: playerItem)

            // Still observe AVPlayer duration as fallback
            observeDuration()

            // Observe time updates
            let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.currentTime = time.seconds
                self?.updateNowPlayingInfo()
            }

            // Load artwork asynchronously once for this episode
            Task {
                cachedArtwork = await loadArtwork()
                updateNowPlayingInfo()
            }
        }

        player?.play()
        player?.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
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
        player?.pause()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentEpisode = nil
        currentPodcast = nil
        cachedArtwork = nil
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

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
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
}
