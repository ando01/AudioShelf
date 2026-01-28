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
                        currentPlayingEpisodeId: viewModel.audioPlayer.currentEpisode?.id,
                        isAudioPlaying: viewModel.audioPlayer.isPlaying,
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
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        // Swipe right to download
                        if viewModel.isDownloaded(episode) {
                            Button(role: .destructive) {
                                viewModel.deleteDownload(for: episode)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } else if !viewModel.isDownloading(episode) {
                            Button {
                                viewModel.downloadEpisode(episode)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .tint(.blue)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // Swipe left to mark as finished
                        if let progress = viewModel.getProgress(for: episode), progress.isFinished {
                            Button {
                                viewModel.clearProgress(for: episode)
                            } label: {
                                Label("Unfinish", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                viewModel.markAsFinished(episode)
                            } label: {
                                Label("Finished", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(viewModel.isOfflineMode ? "\(podcast.title) (Offline)" : podcast.title)
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
    let currentPlayingEpisodeId: String?
    let isAudioPlaying: Bool
    let viewModel: EpisodeDetailViewModel
    let onTap: () -> Void
    let onPlay: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var bookmarks: [Bookmark] = []
    @State private var showClipSheet = false
    @State private var selectedBookmarkForClip: Bookmark?
    @State private var clipEndTime: Double = 0
    @State private var isCreatingClip = false
    @State private var clipError: String?
    private let bookmarkService = BookmarkService.shared
    private let clipService = AudioClipService.shared

    // Computed property to check if this specific episode is playing
    private var isPlaying: Bool {
        currentPlayingEpisodeId == episode.id && isAudioPlaying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Episode title and date
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        // Blue checkmark for downloaded episodes (left side)
                        if viewModel.isDownloaded(episode) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.medium)
                        } else if viewModel.isDownloading(episode) {
                            ProgressView()
                                .scaleEffect(0.7)
                        }

                        Text(episode.displayTitle)
                            .font(.headline)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        // Green checkmark for finished episodes (right side)
                        if let progress = viewModel.getProgress(for: episode), progress.isFinished {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.medium)
                        } else if isPlaying {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.small)
                        }
                    }

                    // PUBLICATION DATE AND DURATION
                    HStack {
                        Text(episode.formattedPublishedDate)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)

                        if episode.durationSeconds != nil {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(episode.formattedDuration)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Progress indicator (if episode has been played but not finished)
                    if let progress = viewModel.getProgress(for: episode),
                       !progress.isFinished,
                       progress.percentComplete > 0 {

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

                // Bookmarks section
                if !bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bookmarks")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        ForEach(bookmarks) { bookmark in
                            HStack(spacing: 8) {
                                Button {
                                    // Jump to bookmark
                                    viewModel.playEpisode(episode)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        viewModel.audioPlayer.seek(to: bookmark.timestamp)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(.blue)
                                            .imageScale(.small)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bookmark.formattedTimestamp)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundStyle(.primary)

                                            if let note = bookmark.note, !note.isEmpty {
                                                Text(note)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "play.circle")
                                            .foregroundStyle(.blue)
                                            .imageScale(.medium)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)

                                // Share clip button
                                Button {
                                    selectedBookmarkForClip = bookmark
                                    // Default end time: 30 seconds after bookmark or end of episode
                                    let defaultDuration = 30.0
                                    if let duration = episode.durationSeconds {
                                        clipEndTime = min(bookmark.timestamp + defaultDuration, duration)
                                    } else {
                                        clipEndTime = bookmark.timestamp + defaultDuration
                                    }
                                    showClipSheet = true
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(.blue)
                                        .imageScale(.small)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    bookmarkService.deleteBookmark(bookmark)
                                    loadBookmarks()
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                        .imageScale(.small)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

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
        .onAppear {
            loadBookmarks()
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                loadBookmarks()
                // Pre-buffering is triggered by the parent view
            }
        }
        .sheet(isPresented: $showClipSheet) {
            if let bookmark = selectedBookmarkForClip {
                ClipConfigurationSheet(
                    episode: episode,
                    podcast: viewModel.podcast,
                    startTime: bookmark.timestamp,
                    endTime: $clipEndTime,
                    isCreating: $isCreatingClip,
                    errorMessage: $clipError,
                    onDismiss: {
                        showClipSheet = false
                        selectedBookmarkForClip = nil
                        clipError = nil
                    }
                )
            }
        }
    }

    private func loadBookmarks() {
        bookmarks = bookmarkService.getBookmarks(for: episode.id)
    }
}

struct ClipConfigurationSheet: View {
    let episode: Episode
    let podcast: Podcast
    let startTime: Double
    @Binding var endTime: Double
    @Binding var isCreating: Bool
    @Binding var errorMessage: String?
    let onDismiss: () -> Void

    private let clipService = AudioClipService.shared
    private let downloadManager = EpisodeDownloadManager.shared
    @State private var clipDuration: Double = 30.0
    @State private var clipURL: URL?

    private var isEpisodeDownloaded: Bool {
        downloadManager.getLocalURL(for: episode.id) != nil
    }

    private var maxDuration: Double {
        if let duration = episode.durationSeconds {
            return min(300, duration - startTime) // Max 5 minutes or remaining episode
        }
        return 300
    }

    private var formattedStartTime: String {
        clipService.formatTime(startTime)
    }

    private var formattedEndTime: String {
        clipService.formatTime(startTime + clipDuration)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Episode info
                VStack(spacing: 8) {
                    Text(episode.displayTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(podcast.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                // Time range display
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formattedStartTime)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("End")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formattedEndTime)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal)

                    // Duration slider
                    VStack(spacing: 8) {
                        Text("Clip Duration: \(Int(clipDuration)) seconds")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Slider(value: $clipDuration, in: 5...maxDuration, step: 5)
                            .tint(.blue)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                if !isEpisodeDownloaded {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text("Episode must be downloaded to create clips")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("Swipe right on the episode and tap Download")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Create and Share button
                Button {
                    createAndShareClip()
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isCreating ? "Creating Clip..." : "Create & Share Clip")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || !isEpisodeDownloaded)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Share Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .disabled(isCreating)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isCreating)
    }

    private func createAndShareClip() {
        // Use local downloaded file (required for clip creation)
        guard let localURL = downloadManager.getLocalURL(for: episode.id) else {
            errorMessage = "Episode must be downloaded first"
            return
        }

        isCreating = true
        errorMessage = nil

        let calculatedEndTime = startTime + clipDuration

        clipService.createClip(
            episodeId: episode.id,
            audioURL: localURL,
            startTime: startTime,
            endTime: calculatedEndTime
        ) { result in
            switch result {
            case .success(let url):
                clipURL = url
                shareClip(url: url)
            case .failure(let error):
                isCreating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func shareClip(url: URL) {
        // Get the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            isCreating = false
            errorMessage = "Cannot present share sheet"
            return
        }

        // Reset creating state
        isCreating = false

        // Store clip info for sharing after dismissal
        let episodeTitle = episode.displayTitle
        let podcastTitle = podcast.title
        let clipStartTime = startTime
        let clipEndTime = startTime + clipDuration

        // Dismiss our configuration sheet first
        onDismiss()

        // After a brief delay for dismiss animation, present share sheet from root
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Find the topmost view controller after our sheet is dismissed
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            self.clipService.shareClip(
                clipURL: url,
                episodeTitle: episodeTitle,
                podcastTitle: podcastTitle,
                startTime: clipStartTime,
                endTime: clipEndTime,
                from: topVC
            ) { _ in
                // Share completed or cancelled - nothing more to do
            }
        }
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
