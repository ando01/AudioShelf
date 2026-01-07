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
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        currentTime = time
    }

    private func observeDuration() {
        guard let currentItem = player?.currentItem else { return }

        // Observe duration
        Task { @MainActor in
            for await _ in currentItem.publisher(for: \.status).values {
                if currentItem.status == .readyToPlay {
                    self.duration = currentItem.duration.seconds
                }
            }
        }
    }
}
