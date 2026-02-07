//
//  PodcastSearchView.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import SwiftUI

struct PodcastSearchView: View {
    @State private var viewModel = PodcastSearchViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search podcasts...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            viewModel.search()
                        }

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.regularMaterial)
                .cornerRadius(12)
                .padding()

                // Results
                if viewModel.isSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                    Spacer()
                } else if viewModel.searchResults.isEmpty && !viewModel.searchText.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No podcasts found for \"\(viewModel.searchText)\"")
                    }
                    Spacer()
                } else if viewModel.searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("Search iTunes for podcasts")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Find and add podcasts to your library")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.searchResults) { result in
                            PodcastSearchResultRow(
                                result: result,
                                isAdding: viewModel.isAddingPodcast,
                                onAdd: {
                                    Task {
                                        await viewModel.addPodcast(result)
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.search()
            }
            .alert("Podcast Added", isPresented: $viewModel.addSuccess) {
                Button("OK") {
                    viewModel.resetAddStatus()
                }
            } message: {
                if let title = viewModel.addedPodcastTitle {
                    Text("\"\(title)\" has been added to your library.")
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.addError != nil },
                set: { if !$0 { viewModel.addError = nil } }
            )) {
                Button("OK") {
                    viewModel.addError = nil
                }
            } message: {
                if let error = viewModel.addError {
                    Text(error)
                }
            }
        }
        .task {
            await viewModel.loadLibraries()
        }
    }
}

struct PodcastSearchResultRow: View {
    let result: PodcastSearchResult
    let isAdding: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover image
            AsyncImage(url: URL(string: result.cover ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.gray)
                    }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(result.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(result.trackCount) episodes")
                        .font(.caption)
                        .foregroundStyle(.blue)

                    if result.explicit {
                        Text("E")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Add button
            Button {
                onAdd()
            } label: {
                if isAdding {
                    ProgressView()
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .disabled(isAdding)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PodcastSearchView()
}
