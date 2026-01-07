//
//  AudioPlayer.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import AVFoundation
import Combine
import Foundation

@Observable
class AudioPlayer {
    private var player: AVPlayer?
    private var timeObserver: Any?

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var currentEpisode: Episode?

    func play(episode: Episode, audioURL: URL) {
        // If playing a different episode, create new player
        if currentEpisode?.id != episode.id {
            stop()
            currentEpisode = episode

            let playerItem = AVPlayerItem(url: audioURL)
            player = AVPlayer(playerItem: playerItem)

            // Observe duration
            observeDuration()

            // Observe time updates
            let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.currentTime = time.seconds
            }
        }

        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
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

        // Observe duration changes
        Task { @MainActor in
            for await _ in currentItem.publisher(for: \.status).values {
                if currentItem.status == .readyToPlay {
                    let itemDuration = currentItem.duration.seconds
                    if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                        self.duration = itemDuration
                        print("Duration loaded: \(itemDuration) seconds")
                    }
                }
            }
        }

        // Also observe duration directly in case it becomes available later
        Task { @MainActor in
            for await _ in currentItem.publisher(for: \.duration).values {
                let itemDuration = currentItem.duration.seconds
                if !itemDuration.isNaN && !itemDuration.isInfinite && itemDuration > 0 {
                    self.duration = itemDuration
                    print("Duration updated: \(itemDuration) seconds")
                }
            }
        }
    }
}
