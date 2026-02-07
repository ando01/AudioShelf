//
//  CarPlaySceneDelegate.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-08.
//

import CarPlay
import UIKit

@objc(CarPlaySceneDelegate)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var allPodcasts: [Podcast] = []  // All podcasts (unfiltered)
    private var filteredPodcasts: [Podcast] = []  // Currently displayed podcasts
    private var artworkCache: [String: UIImage] = [:]

    // Genre filtering
    private var selectedGenre: String? = nil  // nil means "All Genres"

    // Speed control
    private let availableSpeeds: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private var availableGenres: [String] {
        let genres = Set(allPodcasts.flatMap { $0.media.metadata.genres ?? [] })
        return genres.sorted()
    }

    // MARK: - CPTemplateApplicationSceneDelegate

    @objc func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("CarPlay: Did connect")
        self.interfaceController = interfaceController

        // Set root template immediately on main thread
        DispatchQueue.main.async { [weak self] in
            self?.setupRootTemplate()
            self?.configureNowPlayingTemplate()
            self?.loadPodcastData()
        }
    }

    @objc func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        print("CarPlay: Did disconnect")
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([])
        self.interfaceController = nil
        self.allPodcasts = []
        self.filteredPodcasts = []
        self.artworkCache = [:]
        self.selectedGenre = nil
    }

    // MARK: - Template Setup

    private func setupRootTemplate() {
        print("CarPlay: Setting up root template")

        // Create loading state
        let loadingItem = CPListItem(text: "Loading...", detailText: "Please wait")
        loadingItem.isEnabled = false

        let podcastsTemplate = CPListTemplate(
            title: "Podcasts",
            sections: [CPListSection(items: [loadingItem])]
        )

        // Set the list template as root (CPNowPlayingTemplate is shown automatically by the system)
        interfaceController?.setRootTemplate(podcastsTemplate, animated: false) { success, error in
            if let error = error {
                print("CarPlay: Failed to set root template - \(error.localizedDescription)")
            } else {
                print("CarPlay: Root template set successfully")
            }
        }
    }

    // MARK: - Data Loading

    private func loadPodcastData() {
        print("CarPlay: Loading podcast data")

        guard AudioBookshelfAPI.shared.isLoggedIn else {
            print("CarPlay: Not logged in")
            updatePodcastList(with: [], message: "Please log in to the app first")
            return
        }

        Task {
            do {
                // Load libraries
                let libraries = try await AudioBookshelfAPI.shared.getLibraries()
                print("CarPlay: Found \(libraries.count) libraries")

                // Find podcast library
                guard let podcastLibrary = libraries.first(where: { $0.mediaType == "podcast" }) else {
                    print("CarPlay: No podcast library found")
                    await MainActor.run {
                        self.updatePodcastList(with: [], message: "No podcast library found")
                    }
                    return
                }

                // Load podcasts
                let podcasts = try await AudioBookshelfAPI.shared.getPodcasts(libraryId: podcastLibrary.id)
                print("CarPlay: Found \(podcasts.count) podcasts")

                await MainActor.run {
                    self.allPodcasts = podcasts
                    self.applyGenreFilter()
                }
            } catch {
                print("CarPlay: Error loading data - \(error.localizedDescription)")
                await MainActor.run {
                    self.updatePodcastList(with: [], message: "Failed to load podcasts")
                }
            }
        }
    }

    // MARK: - Genre Filtering

    private func applyGenreFilter() {
        if let genre = selectedGenre {
            filteredPodcasts = allPodcasts.filter { podcast in
                podcast.media.metadata.genres?.contains(genre) ?? false
            }
        } else {
            filteredPodcasts = allPodcasts
        }
        updatePodcastList(with: filteredPodcasts, message: nil)
    }

    private func showGenreFilter() {
        print("CarPlay: Showing genre filter with \(availableGenres.count) genres")

        var items: [CPListItem] = []

        // Add "All Genres" option
        let allGenresItem = CPListItem(
            text: "All Genres",
            detailText: selectedGenre == nil ? "Currently selected" : "\(allPodcasts.count) podcasts"
        )
        if selectedGenre == nil {
            allGenresItem.accessoryType = .cloud  // Use as checkmark indicator
        }
        allGenresItem.handler = { [weak self] _, completion in
            self?.selectedGenre = nil
            self?.applyGenreFilter()
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }
        items.append(allGenresItem)

        // Add individual genres
        for genre in availableGenres {
            let podcastCount = allPodcasts.filter { $0.media.metadata.genres?.contains(genre) ?? false }.count
            let item = CPListItem(
                text: genre,
                detailText: selectedGenre == genre ? "Currently selected" : "\(podcastCount) podcasts"
            )
            if selectedGenre == genre {
                item.accessoryType = .cloud  // Use as checkmark indicator
            }
            item.handler = { [weak self] _, completion in
                self?.selectedGenre = genre
                self?.applyGenreFilter()
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
                completion()
            }
            items.append(item)
        }

        let section = CPListSection(items: items)
        let genreTemplate = CPListTemplate(title: "Filter by Genre", sections: [section])

        interfaceController?.pushTemplate(genreTemplate, animated: true) { success, error in
            if let error = error {
                print("CarPlay: Failed to push genre filter - \(error.localizedDescription)")
            }
        }
    }

    private func updatePodcastList(with podcasts: [Podcast], message: String?) {
        print("CarPlay: Updating podcast list with \(podcasts.count) items")

        guard let interfaceController = interfaceController,
              let podcastsTemplate = interfaceController.rootTemplate as? CPListTemplate else {
            print("CarPlay: Cannot update - no template found")
            return
        }

        // Add genre filter button (shows ● when filter is active)
        let filterTitle = selectedGenre != nil ? "Filter ●" : "Filter"
        let filterButton = CPBarButton(title: filterTitle) { [weak self] _ in
            self?.showGenreFilter()
        }
        podcastsTemplate.trailingNavigationBarButtons = [filterButton]

        var items: [CPListItem] = []

        if let message = message {
            let messageItem = CPListItem(text: message, detailText: nil)
            messageItem.isEnabled = false
            items.append(messageItem)
        } else if podcasts.isEmpty {
            let emptyItem = CPListItem(text: "No podcasts found", detailText: selectedGenre != nil ? "Try a different genre" : nil)
            emptyItem.isEnabled = false
            items.append(emptyItem)
        } else {
            for podcast in podcasts {
                let item = CPListItem(text: podcast.title, detailText: podcast.author)
                item.handler = { [weak self] _, completion in
                    self?.showEpisodes(for: podcast)
                    completion()
                }
                items.append(item)
            }
        }

        podcastsTemplate.updateSections([CPListSection(items: items)])
        print("CarPlay: Podcast list updated")
    }

    // MARK: - Episodes

    private func showEpisodes(for podcast: Podcast) {
        print("CarPlay: Showing episodes for \(podcast.title)")

        // Show loading
        let loadingItem = CPListItem(text: "Loading episodes...", detailText: nil)
        loadingItem.isEnabled = false
        let loadingTemplate = CPListTemplate(
            title: podcast.title,
            sections: [CPListSection(items: [loadingItem])]
        )

        interfaceController?.pushTemplate(loadingTemplate, animated: true) { [weak self] success, error in
            if success {
                self?.loadEpisodes(for: podcast)
            } else if let error = error {
                print("CarPlay: Failed to push loading template - \(error.localizedDescription)")
            }
        }
    }

    private func loadEpisodes(for podcast: Podcast) {
        Task {
            do {
                let episodes = try await AudioBookshelfAPI.shared.getEpisodes(podcastId: podcast.id)
                print("CarPlay: Loaded \(episodes.count) episodes")

                await MainActor.run {
                    self.updateEpisodeList(episodes: episodes, podcast: podcast)
                }
            } catch {
                print("CarPlay: Failed to load episodes - \(error.localizedDescription)")
            }
        }
    }

    private func updateEpisodeList(episodes: [Episode], podcast: Podcast) {
        guard let interfaceController = interfaceController,
              let currentTemplate = interfaceController.topTemplate as? CPListTemplate else {
            return
        }

        var items: [CPListItem] = []

        for episode in episodes {
            let item = CPListItem(
                text: episode.displayTitle,
                detailText: episode.formattedPublishedDate
            )
            item.handler = { [weak self] _, completion in
                self?.playEpisode(episode, from: podcast)
                completion()
            }
            items.append(item)
        }

        currentTemplate.updateSections([CPListSection(items: items)])
    }

    // MARK: - Playback

    private func playEpisode(_ episode: Episode, from podcast: Podcast) {
        print("CarPlay: Playing \(episode.displayTitle)")

        let api = AudioBookshelfAPI.shared

        guard let serverURL = api.serverURL else {
            print("CarPlay: No server URL")
            return
        }

        guard let enclosureUrl = episode.enclosure?.url else {
            print("CarPlay: No audio URL")
            return
        }

        let audioURLString: String
        if enclosureUrl.hasPrefix("http://") || enclosureUrl.hasPrefix("https://") {
            audioURLString = enclosureUrl
        } else {
            guard let token = api.authToken else {
                print("CarPlay: No auth token")
                return
            }
            audioURLString = "\(serverURL)\(enclosureUrl)?token=\(token)"
        }

        guard let audioURL = URL(string: audioURLString) else {
            print("CarPlay: Invalid URL")
            return
        }

        AudioPlayer.shared.play(episode: episode, audioURL: audioURL, podcast: podcast)
    }

    // MARK: - Now Playing Controls

    private func configureNowPlayingTemplate() {
        updateNowPlayingButtons()
    }

    private func updateNowPlayingButtons() {
        let nowPlayingTemplate = CPNowPlayingTemplate.shared

        // Speed button - shows current speed, tap to pick from list
        let speedImage = createSpeedImage(for: AudioPlayer.shared.playbackSpeed)
        let speedButton = CPNowPlayingImageButton(image: speedImage) { [weak self] _ in
            self?.showSpeedPicker()
        }

        // Bookmark button - tap to save current position
        let bookmarkImage = UIImage(systemName: "bookmark")?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        let bookmarkButton = CPNowPlayingImageButton(image: bookmarkImage) { [weak self] _ in
            self?.addBookmarkAtCurrentPosition()
        }

        nowPlayingTemplate.updateNowPlayingButtons([speedButton, bookmarkButton])
    }

    // MARK: - Speed Control

    private func formatSpeed(_ speed: Float) -> String {
        let formatted = String(format: "%.2f", speed)
        let trimmed = formatted
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        return "\(trimmed)×"
    }

    private func showSpeedPicker() {
        let currentSpeed = AudioPlayer.shared.playbackSpeed

        var items: [CPListItem] = []
        for speed in availableSpeeds {
            let label = formatSpeed(speed)
            let item = CPListItem(
                text: label,
                detailText: speed == currentSpeed ? "Current speed" : nil
            )
            if speed == currentSpeed {
                item.accessoryType = .cloud
            }
            item.handler = { [weak self] _, completion in
                AudioPlayer.shared.setPlaybackSpeed(speed)
                self?.updateNowPlayingButtons()
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
                print("CarPlay: Playback speed set to \(label)")
                completion()
            }
            items.append(item)
        }

        let section = CPListSection(items: items)
        let speedTemplate = CPListTemplate(title: "Playback Speed", sections: [section])
        interfaceController?.pushTemplate(speedTemplate, animated: true, completion: nil)
    }

    private func createSpeedImage(for speed: Float) -> UIImage {
        let speedText = formatSpeed(speed)
        let size = CGSize(width: 88, height: 88)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let text = NSString(string: speedText)
            let textSize = text.size(withAttributes: attributes)
            let point = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )
            text.draw(at: point, withAttributes: attributes)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    // MARK: - Bookmarks

    private func addBookmarkAtCurrentPosition() {
        guard let episode = AudioPlayer.shared.currentEpisode else {
            print("CarPlay: No episode playing, cannot add bookmark")
            return
        }

        let timestamp = AudioPlayer.shared.currentTime
        BookmarkService.shared.addBookmark(episodeId: episode.id, timestamp: timestamp, note: nil)
        print("CarPlay: Bookmark added at \(Bookmark(episodeId: episode.id, timestamp: timestamp, note: nil).formattedTimestamp)")

        // Show filled bookmark icon briefly as feedback
        let filledImage = UIImage(systemName: "bookmark.fill")?.withRenderingMode(.alwaysTemplate) ?? UIImage()
        let feedbackButton = CPNowPlayingImageButton(image: filledImage) { [weak self] _ in
            self?.addBookmarkAtCurrentPosition()
        }
        let speedImage = createSpeedImage(for: AudioPlayer.shared.playbackSpeed)
        let speedButton = CPNowPlayingImageButton(image: speedImage) { [weak self] _ in
            self?.showSpeedPicker()
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([speedButton, feedbackButton])

        // Revert to outline icon after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateNowPlayingButtons()
        }
    }
}
