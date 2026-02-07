//
//  TVNowPlayingView.swift
//  AudioShelfTV
//
//  Created by Claude on 2026-02-04.
//

import SwiftUI

struct TVNowPlayingView: View {
    var audioPlayer: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                HStack(spacing: 48) {
                    // Left side - artwork
                    coverArtView
                        .frame(width: geometry.size.width * 0.4)

                    // Right side - info and controls
                    VStack(spacing: 32) {
                        Spacer()

                        // Episode info
                        episodeInfoView

                        // Progress
                        progressView

                        // Transport controls
                        transportControls

                        // Speed control
                        speedControl

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(60)
            }
            .navigationTitle("Now Playing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Cover Art

    @ViewBuilder
    private var coverArtView: some View {
        if let podcast = audioPlayer.currentPodcast,
           let coverURL = AudioBookshelfAPI.shared.getCoverImageURL(for: podcast) {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                case .failure:
                    artworkPlaceholder
                case .empty:
                    artworkPlaceholder
                        .overlay { ProgressView() }
                @unknown default:
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.blue.opacity(0.2))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.opacity(0.5))
            }
    }

    // MARK: - Episode Info

    @ViewBuilder
    private var episodeInfoView: some View {
        VStack(spacing: 12) {
            if let episode = audioPlayer.currentEpisode {
                HStack(spacing: 8) {
                    if episode.isVideo {
                        Image(systemName: "video.fill")
                            .foregroundStyle(.purple)
                    }
                    Text(episode.displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
            }

            if let podcast = audioPlayer.currentPodcast {
                Text(podcast.title)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Progress

    private var progressFraction: Double {
        audioPlayer.duration > 0 ? audioPlayer.currentTime / audioPlayer.duration : 0
    }

    private var remainingTimeText: String {
        let remaining = audioPlayer.duration - audioPlayer.currentTime
        return "-\(formatTime(remaining))"
    }

    private var progressView: some View {
        VStack(spacing: 8) {
            ProgressView(value: progressFraction)
                .tint(.blue)

            HStack {
                Text(formatTime(audioPlayer.currentTime))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(remainingTimeText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 60) {
            // Skip backward
            Button {
                audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 44))
            }

            // Play/Pause
            Button {
                if audioPlayer.isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.resume()
                }
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
            }

            // Skip forward
            Button {
                let newTime = audioPlayer.currentTime + 30
                let seekTime = audioPlayer.duration > 0
                    ? min(audioPlayer.duration, newTime)
                    : newTime
                audioPlayer.seek(to: seekTime)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.system(size: 44))
            }
        }
    }

    // MARK: - Speed Control

    private func isCurrentSpeed(_ speed: Double) -> Bool {
        audioPlayer.playbackSpeed == Float(speed)
    }

    private var speedControl: some View {
        HStack(spacing: 16) {
            Text("Speed:")
                .foregroundStyle(.secondary)

            ForEach([0.75, 1.0, 1.25, 1.5, 2.0] as [Double], id: \.self) { speed in
                let selected = isCurrentSpeed(speed)
                Button {
                    audioPlayer.setPlaybackSpeed(Float(speed))
                } label: {
                    Text("\(speed, specifier: "%.2g")×")
                        .fontWeight(selected ? .bold : .regular)
                        .foregroundStyle(selected ? .blue : .primary)
                }
            }
        }
        .font(.headline)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(max(0, seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
