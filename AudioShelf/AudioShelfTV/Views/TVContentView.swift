//
//  TVContentView.swift
//  AudioShelfTV
//
//  Created by Claude on 2026-02-04.
//

import SwiftUI

struct TVContentView: View {
    @Binding var isLoggedIn: Bool
    var audioPlayer: AudioPlayer
    @State private var viewModel = PodcastListViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showSignOutAlert = false
    @State private var showSortOptions = false

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 40)
    ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 24) {
                    // Now Playing banner
                    if let episode = audioPlayer.currentEpisode {
                        NowPlayingBanner(audioPlayer: audioPlayer, episode: episode)
                            .focusable()
                    }

                    // Genre filter
                    if !viewModel.availableGenres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                Button {
                                    viewModel.setGenreFilter(nil)
                                } label: {
                                    Text("All")
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.card)

                                ForEach(viewModel.availableGenres, id: \.self) { genre in
                                    Button {
                                        viewModel.setGenreFilter(genre)
                                    } label: {
                                        Text(genre)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                            .padding(.horizontal, 48)
                        }
                    }

                    // Podcast grid
                    if viewModel.isLoading && viewModel.podcasts.isEmpty {
                        ProgressView("Loading podcasts...")
                            .padding(.top, 100)
                    } else if viewModel.podcasts.isEmpty {
                        ContentUnavailableView {
                            Label("No Podcasts", systemImage: "waveform")
                        } description: {
                            Text("No podcasts found in your library")
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(viewModel.podcasts) { podcast in
                                Button {
                                    navigationPath.append(podcast.id)
                                } label: {
                                    PodcastCardView(podcast: podcast)
                                }
                                .buttonStyle(.card)
                            }
                        }
                        .padding(.horizontal, 48)
                    }
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("AudioShelf")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSortOptions = true
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .alert("Sort Podcasts", isPresented: $showSortOptions) {
                Button("Latest Episode") {
                    viewModel.setSortOption(.latestEpisode)
                }
                Button("Title") {
                    viewModel.setSortOption(.title)
                }
                Button("Genre") {
                    viewModel.setSortOption(.genre)
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    AudioBookshelfAPI.shared.logout()
                    isLoggedIn = false
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .navigationDestination(for: String.self) { podcastId in
                if let podcast = viewModel.podcasts.first(where: { $0.id == podcastId }) {
                    TVEpisodeListView(podcast: podcast, audioPlayer: audioPlayer)
                }
            }
            .task {
                await viewModel.loadLibraries()
            }
        }
    }
}

// MARK: - Podcast Card

struct PodcastCardView: View {
    let podcast: Podcast

    var body: some View {
        VStack(spacing: 12) {
            // Cover art
            AsyncImage(url: AudioBookshelfAPI.shared.getCoverImageURL(for: podcast)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.2))
                        .overlay {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue.opacity(0.5))
                        }
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 250, height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Podcast info
            VStack(spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 250)
        }
    }
}

// MARK: - Now Playing Banner

struct NowPlayingBanner: View {
    var audioPlayer: AudioPlayer
    let episode: Episode

    var body: some View {
        HStack(spacing: 16) {
            if episode.isVideo {
                Image(systemName: "video.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                if let podcast = audioPlayer.currentPodcast {
                    Text(podcast.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                if audioPlayer.isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.resume()
                }
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 48)
    }
}
