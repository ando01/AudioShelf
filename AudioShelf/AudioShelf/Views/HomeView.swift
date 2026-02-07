//
//  HomeView.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    var audioPlayer: AudioPlayer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.isLoading && viewModel.podcasts.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading...")
                            Spacer()
                        }
                        .padding(.top, 100)
                    } else if let error = viewModel.errorMessage {
                        ContentUnavailableView {
                            Label("Error", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Retry") {
                                Task {
                                    await viewModel.refresh()
                                }
                            }
                        }
                    } else {
                        // Recently Updated Section
                        if !viewModel.carouselPodcasts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recently Updated")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                PodcastCarousel(
                                    podcasts: viewModel.carouselPodcasts,
                                    audioPlayer: audioPlayer
                                )
                            }
                            .padding(.top, 8)
                        }

                        // Continue Listening Section (placeholder for future)
                        // This could be expanded to show in-progress episodes
                    }
                }
            }
            .navigationTitle(viewModel.isOfflineMode ? "Home (Offline)" : "Home")
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
}

#Preview {
    HomeView(audioPlayer: AudioPlayer.shared)
}
