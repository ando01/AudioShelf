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
    @State private var audioPlayer = AudioPlayer()

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

                // Progress bar
                ProgressView(value: audioPlayer.currentTime, total: audioPlayer.duration)
                    .tint(.blue)

                // Controls
                HStack(spacing: 30) {
                    // Skip backward 15s
                    Button {
                        audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                    }

                    Spacer()

                    // Play/Pause button
                    Button {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.resume()
                        }
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    // Skip forward 30s
                    Button {
                        let newTime = audioPlayer.currentTime + 30
                        let seekTime = audioPlayer.duration > 0
                            ? min(audioPlayer.duration, newTime)
                            : newTime
                        audioPlayer.seek(to: seekTime)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.title3)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }
}
