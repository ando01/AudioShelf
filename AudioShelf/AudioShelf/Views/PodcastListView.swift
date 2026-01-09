//
//  PodcastListView.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI

struct PodcastListView: View {
    @State private var viewModel = PodcastListViewModel()
    @Binding var isLoggedIn: Bool
    var audioPlayer: AudioPlayer

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.podcasts.isEmpty {
                    ProgressView("Loading podcasts...")
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                    }
                } else if viewModel.podcasts.isEmpty {
                    ContentUnavailableView {
                        Label("No Podcasts", systemImage: "mic.slash")
                    } description: {
                        Text("No podcasts found in this library")
                    }
                } else {
                    List {
                        ForEach(viewModel.podcasts) { podcast in
                            NavigationLink {
                                EpisodeDetailView(podcast: podcast, audioPlayer: audioPlayer)
                            } label: {
                                PodcastRow(podcast: podcast)
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .navigationTitle(viewModel.isOfflineMode ? "Podcasts (Offline)" : "Podcasts")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        TextField("Search podcasts", text: $viewModel.searchText)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            viewModel.setGenreFilter(nil)
                        } label: {
                            HStack {
                                Text("All Genres")
                                if viewModel.selectedGenre == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Divider()

                        ForEach(viewModel.availableGenres, id: \.self) { genre in
                            Button {
                                viewModel.setGenreFilter(genre)
                            } label: {
                                HStack {
                                    Text(genre)
                                    if viewModel.selectedGenre == genre {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(viewModel.selectedGenre ?? "All Genres")
                                .font(.subheadline)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Sort options
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button {
                                    viewModel.setSortOption(option)
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if option == viewModel.sortOption {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Sort By", systemImage: "arrow.up.arrow.down")
                        }

                        Divider()

                        // Library selection
                        ForEach(viewModel.libraries.filter { $0.isPodcastLibrary }) { library in
                            Button {
                                Task {
                                    await viewModel.loadPodcasts(for: library)
                                }
                            } label: {
                                HStack {
                                    Text(library.name)
                                    if library.id == viewModel.selectedLibrary?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        Divider()

                        Button("Logout", role: .destructive) {
                            viewModel.logout()
                            isLoggedIn = false
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await viewModel.loadLibraries()
        }
    }
}

struct PodcastRow: View {
    let podcast: Podcast

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover image
            AsyncImage(url: AudioBookshelfAPI.shared.getCoverImageURL(for: podcast)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.gray)
                    }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Genre badge
                Text(podcast.primaryGenre)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PodcastListView(isLoggedIn: .constant(true), audioPlayer: AudioPlayer.shared)
}
