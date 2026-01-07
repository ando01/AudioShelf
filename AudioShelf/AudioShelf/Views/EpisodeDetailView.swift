//
//  EpisodeDetailView.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI

struct EpisodeDetailView: View {
    let podcast: Podcast
    @State private var viewModel = EpisodeDetailViewModel()
    @State private var expandedEpisodeId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Episode list
            Group {
                if viewModel.isLoading && viewModel.episodes.isEmpty {
                    ProgressView("Loading episodes...")
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
                    List {
                        ForEach(viewModel.episodes) { episode in
                            EpisodeRow(
                                episode: episode,
                                isExpanded: expandedEpisodeId == episode.id,
                                isPlaying: viewModel.audioPlayer.currentEpisode?.id == episode.id && viewModel.audioPlayer.isPlaying
                            ) {
                                withAnimation {
                                    if expandedEpisodeId == episode.id {
                                        expandedEpisodeId = nil
                                    } else {
                                        expandedEpisodeId = episode.id
                                    }
                                }
                            } onPlay: {
                                viewModel.playEpisode(episode)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }

            // Audio player controls (shown when playing)
            if viewModel.audioPlayer.currentEpisode != nil {
                MiniPlayerView(viewModel: viewModel)
            }
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadEpisodes(for: podcast.id)
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let isExpanded: Bool
    let isPlaying: Bool
    let onTap: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Episode title and date
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(episode.displayTitle)
                            .font(.headline)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        if isPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.small)
                        }
                    }

                    // PUBLICATION DATE - PROMINENTLY DISPLAYED
                    HStack {
                        Text(episode.formattedPublishedDate)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)

                        if let duration = episode.duration {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(episode.formattedDuration)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()

                if let description = episode.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                Button {
                    onPlay()
                } label: {
                    HStack {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(isPlaying ? "Pause" : "Play Episode")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

struct MiniPlayerView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 12) {
                if let episode = viewModel.audioPlayer.currentEpisode {
                    Text(episode.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                // Progress bar
                if viewModel.audioPlayer.duration > 0 {
                    ProgressView(value: viewModel.audioPlayer.currentTime, total: viewModel.audioPlayer.duration)
                        .tint(.blue)
                } else {
                    ProgressView(value: 0, total: 1)
                        .tint(.blue)
                }

                // Time labels
                HStack {
                    Text(formatTime(viewModel.audioPlayer.currentTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(viewModel.audioPlayer.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Controls
                HStack(spacing: 40) {
                    Button {
                        viewModel.audioPlayer.seek(to: max(0, viewModel.audioPlayer.currentTime - 15))
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }

                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }

                    Button {
                        viewModel.audioPlayer.seek(to: min(viewModel.audioPlayer.duration, viewModel.audioPlayer.currentTime + 30))
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.title2)
                    }
                }
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

#Preview {
    NavigationStack {
        EpisodeDetailView(podcast: Podcast(
            id: "1",
            media: PodcastMedia(
                metadata: PodcastMetadata(
                    title: "Sample Podcast",
                    author: "Sample Author",
                    description: nil,
                    imageUrl: nil
                ),
                episodes: nil
            ),
            mediaType: "podcast",
            addedAt: 0,
            recentEpisode: nil
        ))
    }
}
