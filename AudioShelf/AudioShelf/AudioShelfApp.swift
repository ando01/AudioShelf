//
//  AudioShelfApp.swift
//  AudioShelf
//
//  Created by Andrew Melton on 1/7/26.
//

import SwiftUI

@main
struct AudioShelfApp: App {
    @State private var isLoggedIn = AudioBookshelfAPI.shared.isLoggedIn
    private var audioPlayer = AudioPlayer.shared

    var body: some Scene {
        WindowGroup {
            RootView(isLoggedIn: $isLoggedIn, audioPlayer: audioPlayer)
        }
    }
}

struct RootView: View {
    @Binding var isLoggedIn: Bool
    @Bindable var audioPlayer: AudioPlayer

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            if isLoggedIn {
                PodcastListView(isLoggedIn: $isLoggedIn, audioPlayer: audioPlayer)
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }

            // Persistent mini player at bottom
            if audioPlayer.currentEpisode != nil {
                GlobalMiniPlayerView(audioPlayer: audioPlayer)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: audioPlayer.currentEpisode != nil)
    }
}

struct GlobalMiniPlayerView: View {
    @Bindable var audioPlayer: AudioPlayer
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 8) {
                // Episode info
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let episode = audioPlayer.currentEpisode {
                            Text(episode.displayTitle)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        if let podcast = audioPlayer.currentPodcast {
                            Text(podcast.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }

                // Progress bar (draggable slider) with time labels
                HStack(spacing: 8) {
                    Text(formatTime(isDragging ? dragValue : audioPlayer.currentTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)

                    Slider(
                        value: isDragging ? $dragValue : Binding(
                            get: { audioPlayer.currentTime },
                            set: { _ in }
                        ),
                        in: 0...max(audioPlayer.duration, 1)
                    ) { isEditing in
                        isDragging = isEditing
                        if !isEditing {
                            audioPlayer.seek(to: dragValue)
                        } else {
                            dragValue = audioPlayer.currentTime
                        }
                    }
                    .tint(.blue)

                    Text(formatTime(audioPlayer.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                }

                // Controls - centered play button with symmetric layout
                HStack(spacing: 0) {
                    // Left side - Skip backward
                    HStack {
                        Button {
                            audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                    // Center - Play/Pause button
                    Button {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.resume()
                        }
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 70)

                    // Right side - Speed and Skip forward
                    HStack(spacing: 16) {
                        Spacer()

                        // Playback speed
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                                Button {
                                    audioPlayer.setPlaybackSpeed(Float(speed))
                                } label: {
                                    HStack {
                                        Text("\(speed, specifier: "%.2g")×")
                                        if audioPlayer.playbackSpeed == Float(speed) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text("\(audioPlayer.playbackSpeed, specifier: "%.2g")×")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                                .frame(minWidth: 36)
                        }

                        // Skip forward 30s
                        Button {
                            let newTime = audioPlayer.currentTime + 30
                            let seekTime = audioPlayer.duration > 0
                                ? min(audioPlayer.duration, newTime)
                                : newTime
                            audioPlayer.seek(to: seekTime)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.title2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
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
}
