//
//  CarPlayTemplateManager.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-08.
//

import CarPlay
import UIKit

@MainActor
class CarPlayTemplateManager {
    private let api = AudioBookshelfAPI.shared
    private var artworkCache: [String: UIImage] = [:]

    // MARK: - Tab Bar Template

    func createTabBarTemplate(podcastsTemplate: CPListTemplate, nowPlayingTemplate: CPNowPlayingTemplate) -> CPTabBarTemplate {
        podcastsTemplate.tabTitle = "Podcasts"
        podcastsTemplate.tabImage = UIImage(systemName: "headphones")

        nowPlayingTemplate.tabTitle = "Now Playing"
        nowPlayingTemplate.tabImage = UIImage(systemName: "play.circle.fill")

        return CPTabBarTemplate(templates: [podcastsTemplate, nowPlayingTemplate])
    }

    // MARK: - Podcast List Template

    func createPodcastListTemplate(
        podcasts: [Podcast],
        onSelectPodcast: @escaping (Podcast) -> Void,
        onGenreFilter: @escaping () -> Void,
        onSortOptions: @escaping () -> Void
    ) -> CPListTemplate {
        let items = podcasts.map { podcast in
            createPodcastListItem(podcast: podcast, onSelect: onSelectPodcast)
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Podcasts", sections: [section])

        // Add trailing button for genre filter
        let genreButton = CPBarButton(title: "Filter") { _ in
            onGenreFilter()
        }

        // Add trailing button for sort options
        let sortButton = CPBarButton(title: "Sort") { _ in
            onSortOptions()
        }

        template.trailingNavigationBarButtons = [sortButton, genreButton]

        return template
    }

    private func createPodcastListItem(podcast: Podcast, onSelect: @escaping (Podcast) -> Void) -> CPListItem {
        let item = CPListItem(
            text: podcast.title,
            detailText: podcast.author
        )

        // Load artwork asynchronously
        Task {
            if let artwork = await loadArtwork(for: podcast) {
                item.setImage(artwork)
            }
        }

        item.handler = { [weak item] _, completion in
            onSelect(podcast)
            completion()
        }

        return item
    }

    // MARK: - Episode List Template

    func createEpisodeListTemplate(
        podcast: Podcast,
        episodes: [Episode],
        onSelectEpisode: @escaping (Episode) -> Void
    ) -> CPListTemplate {
        let items = episodes.map { episode in
            createEpisodeListItem(episode: episode, onSelect: onSelectEpisode)
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: podcast.title, sections: [section])

        return template
    }

    private func createEpisodeListItem(episode: Episode, onSelect: @escaping (Episode) -> Void) -> CPListItem {
        let item = CPListItem(
            text: episode.displayTitle,
            detailText: episode.formattedPublishedDate
        )

        item.handler = { [weak item] _, completion in
            onSelect(episode)
            completion()
        }

        return item
    }

    // MARK: - Now Playing Template

    func createNowPlayingTemplate() -> CPNowPlayingTemplate {
        return CPNowPlayingTemplate.shared
    }

    // MARK: - Action Sheets & Alerts

    func createGenreFilterActionSheet(
        availableGenres: [String],
        currentGenre: String?,
        onSelectGenre: @escaping (String?) -> Void
    ) -> CPActionSheetTemplate {
        var actions: [CPAlertAction] = []

        // Add "All Genres" option
        let allGenresAction = CPAlertAction(title: "All Genres", style: .default) { _ in
            onSelectGenre(nil)
        }
        actions.append(allGenresAction)

        // Add individual genres
        for genre in availableGenres {
            let action = CPAlertAction(title: genre, style: .default) { _ in
                onSelectGenre(genre)
            }
            actions.append(action)
        }

        // Add cancel action
        let cancelAction = CPAlertAction(title: "Cancel", style: .cancel) { _ in }
        actions.append(cancelAction)

        return CPActionSheetTemplate(title: "Filter by Genre", message: nil, actions: actions)
    }

    func createSortOptionsActionSheet(
        currentSort: SortOption,
        onSelectSort: @escaping (SortOption) -> Void
    ) -> CPActionSheetTemplate {
        var actions: [CPAlertAction] = []

        for sortOption in SortOption.allCases {
            let action = CPAlertAction(title: sortOption.rawValue, style: .default) { _ in
                onSelectSort(sortOption)
            }
            actions.append(action)
        }

        let cancelAction = CPAlertAction(title: "Cancel", style: .cancel) { _ in }
        actions.append(cancelAction)

        return CPActionSheetTemplate(title: "Sort By", message: nil, actions: actions)
    }

    func createErrorAlert(message: String) -> CPAlertTemplate {
        let action = CPAlertAction(title: "OK", style: .default) { _ in }
        return CPAlertTemplate(titleVariants: ["Error"], actions: [action])
    }

    // MARK: - Artwork Loading

    func loadArtwork(for podcast: Podcast) async -> UIImage? {
        // Check cache first
        if let cached = artworkCache[podcast.id] {
            return cached
        }

        // Load from network
        guard let url = api.getCoverImageURL(for: podcast) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                // Resize for CarPlay (recommended 120x120 points)
                let resized = resizeImage(image, to: CGSize(width: 120, height: 120))
                artworkCache[podcast.id] = resized
                return resized
            }
        } catch {
            print("Failed to load artwork for podcast \(podcast.title): \(error)")
        }

        return nil
    }

    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Cache Management

    func clearArtworkCache() {
        artworkCache.removeAll()
    }
}
