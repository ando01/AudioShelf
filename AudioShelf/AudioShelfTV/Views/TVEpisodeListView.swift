//
//  TVEpisodeListView.swift
//  AudioShelfTV
//
//  Created by Claude on 2026-02-04.
//

import SwiftUI
import AVKit

struct TVEpisodeListView: View {
    let podcast: Podcast
    var audioPlayer: AudioPlayer
    @State private var viewModel: EpisodeDetailViewModel
    @State private var showVideoPlayer = false
    @State private var showAudioPlayer = false
    @State private var selectedVideoEpisode: Episode?

    init(podcast: Podcast, audioPlayer: AudioPlayer) {
        self.podcast = podcast
        self.audioPlayer = audioPlayer
        self._viewModel = State(initialValue: EpisodeDetailViewModel(audioPlayer: audioPlayer, podcast: podcast))
    }

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.episodes.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading episodes...")
                    Spacer()
                }
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else if viewModel.episodes.isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("No episodes found for this podcast")
                }
            } else {
                ForEach(viewModel.episodes) { episode in
                    Button {
                        if episode.isVideo {
                            // Play episode and present full-screen video player
                            viewModel.playEpisode(episode)
                            selectedVideoEpisode = episode
                            showVideoPlayer = true
                        } else {
                            // Play episode and present audio player controls
                            viewModel.playEpisode(episode)
                            showAudioPlayer = true
                        }
                    } label: {
                        TVEpisodeRowView(
                            episode: episode,
                            currentPlayingEpisodeId: audioPlayer.currentEpisode?.id,
                            isAudioPlaying: audioPlayer.isPlaying,
                            viewModel: viewModel
                        )
                    }
                    .buttonStyle(.card)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(podcast.title)
        .task {
            await viewModel.loadEpisodes(for: podcast.id)
        }
        .fullScreenCover(isPresented: $showVideoPlayer) {
            TVVideoPlayerView(player: audioPlayer.avPlayer)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showAudioPlayer) {
            TVNowPlayingView(audioPlayer: audioPlayer)
        }
    }
}

// MARK: - Episode Row

struct TVEpisodeRowView: View {
    let episode: Episode
    let currentPlayingEpisodeId: String?
    let isAudioPlaying: Bool
    let viewModel: EpisodeDetailViewModel

    private var isPlaying: Bool {
        currentPlayingEpisodeId == episode.id && isAudioPlaying
    }

    var body: some View {
        HStack(spacing: 16) {
            // Media type icon
            Image(systemName: episode.isVideo ? "video.fill" : "waveform")
                .foregroundStyle(episode.isVideo ? .purple : .blue)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                // Date and duration
                HStack(spacing: 8) {
                    Text(episode.formattedPublishedDate)
                        .font(.subheadline)
                        .foregroundStyle(.blue)

                    if episode.durationSeconds != nil {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(episode.formattedDuration)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if episode.isVideo {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("Video")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.purple)
                    }
                }

                // Progress bar
                if let progress = viewModel.getProgress(for: episode),
                   !progress.isFinished,
                   progress.percentComplete > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: progress.percentComplete)
                            .tint(.blue)

                        Text(progress.formattedProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer()

            // Status icons
            HStack(spacing: 12) {
                if let progress = viewModel.getProgress(for: episode), progress.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
