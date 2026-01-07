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

@Observable
class AudioPlayer {
    private var player: AVPlayer?
    private var timeObserver: Any?

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var currentEpisode: Episode?

    init() {
        configureAudioSession()
        setupRemoteCommandCenter()
    }

    func play(episode: Episode, audioURL: URL) {
        // If playing a different episode, create new player
        if currentEpisode?.id != episode.id {
            stop()
            currentEpisode = episode

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
        }

        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
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
            if let episode = self?.currentEpisode {
                // Resume playback
                self?.player?.play()
                self?.isPlaying = true
                self?.updateNowPlayingInfo()
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        // Add artwork if available (using a placeholder for now)
        if let image = UIImage(systemName: "mic.fill") {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
