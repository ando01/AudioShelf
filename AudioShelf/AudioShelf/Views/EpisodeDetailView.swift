//
//  EpisodeDetailView.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI

// Helper to convert HTML to AttributedString with formatting and clickable links
extension String {
    func htmlToAttributedString(colorScheme: ColorScheme) -> AttributedString {
        guard let data = self.data(using: .utf8) else {
            return AttributedString(self)
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let nsAttributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            // Convert NSAttributedString to AttributedString
            if var attributedString = try? AttributedString(nsAttributedString, including: \.uiKit) {
                // Set appropriate text color and font size based on color scheme
                let textColor: Color = colorScheme == .dark ? .white : .black
                let fontSize: CGFloat = 22

                // Apply color and font size to all runs
                for run in attributedString.runs {
                    // Apply font size to all text
                    attributedString[run.range].font = .systemFont(ofSize: fontSize)

                    // Only apply text color if it's not a link (preserve link colors)
                    if run.link == nil {
                        attributedString[run.range].foregroundColor = textColor
                    }
                }
                return attributedString
            }
        }

        return AttributedString(self)
    }
}

struct EpisodeDetailView: View {
    let podcast: Podcast
    var audioPlayer: AudioPlayer
    @State private var viewModel: EpisodeDetailViewModel
    @State private var expandedEpisodeId: String?

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
                    EpisodeRow(
                        episode: episode,
                        isExpanded: expandedEpisodeId == episode.id,
                        isPlaying: viewModel.audioPlayer.currentEpisode?.id == episode.id && viewModel.audioPlayer.isPlaying,
                        viewModel: viewModel
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
        }
        .listStyle(.plain)
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    TextField("Search episodes", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                            viewModel.setSearchText("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(8)
                .background(.regularMaterial)
                .cornerRadius(10)
                .frame(maxWidth: 400)
            }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.setSearchText(newValue)
        }
        .task {
            await viewModel.loadEpisodes(for: podcast.id)
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let isExpanded: Bool
    let isPlaying: Bool
    let viewModel: EpisodeDetailViewModel
    let onTap: () -> Void
    let onPlay: () -> Void

    @Environment(\.colorScheme) private var colorScheme

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

                    // Progress indicator (if episode has been played)
                    if let progress = PlaybackProgressService.shared.getProgress(episodeId: episode.id),
                       progress.percentComplete < 0.95 {  // Don't show for completed

                        HStack(spacing: 8) {
                            ProgressView(value: progress.percentComplete)
                                .tint(.blue)
                                .frame(height: 2)

                            Text(progress.formattedProgress)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()

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

                // Action buttons row
                HStack(spacing: 12) {
                    // Download button
                    if viewModel.isDownloaded(episode) {
                        Button {
                            viewModel.deleteDownload(for: episode)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Downloaded")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    } else if viewModel.isDownloading(episode) {
                        Button {} label: {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Downloading...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)
                    } else {
                        Button {
                            viewModel.downloadEpisode(episode)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                Text("Download")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }

                    // Mark as finished button
                    if let progress = viewModel.getProgress(for: episode), progress.isFinished {
                        Button {
                            viewModel.clearProgress(for: episode)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Finished")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    } else {
                        Button {
                            viewModel.markAsFinished(episode)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Mark Finished")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)

                if let description = episode.description, !description.isEmpty {
                    Text(description.htmlToAttributedString(colorScheme: colorScheme))
                        .font(.system(size: 22))
                        .lineSpacing(8)
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                        .tint(.blue)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        EpisodeDetailView(
            podcast: Podcast(
                id: "1",
                media: PodcastMedia(
                    metadata: PodcastMetadata(
                        title: "Sample Podcast",
                        author: "Sample Author",
                        description: nil,
                        imageUrl: nil,
                        genres: nil
                    ),
                    episodes: nil
                ),
                mediaType: "podcast",
                addedAt: 0,
                recentEpisode: nil
            ),
            audioPlayer: AudioPlayer.shared
        )
    }
}
