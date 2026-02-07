//
//  PodcastCarousel.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import SwiftUI

struct PodcastCarousel: View {
    let podcasts: [Podcast]
    var audioPlayer: AudioPlayer

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(podcasts) { podcast in
                    NavigationLink {
                        EpisodeDetailView(podcast: podcast, audioPlayer: audioPlayer)
                    } label: {
                        PodcastCarouselCard(podcast: podcast)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct PodcastCarouselCard: View {
    let podcast: Podcast

    var body: some View {
        AsyncImage(url: AudioBookshelfAPI.shared.getCoverImageURL(for: podcast)) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                    }
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
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    NavigationStack {
        PodcastCarousel(podcasts: [], audioPlayer: AudioPlayer.shared)
    }
}
