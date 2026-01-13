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
    private let api = AudioBookshelfAPI.shared
    private let audioPlayer = AudioPlayer.shared
    private let templateManager = CarPlayTemplateManager()

    private var interfaceController: CPInterfaceController?
    private var podcastListViewModel: PodcastListViewModel?

    // MARK: - Scene Lifecycle

    @objc func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("🚗 CarPlay delegate method called - didConnect")
        self.interfaceController = interfaceController

        print("🚗 CarPlay connected - interface controller set")

        // Initialize view model
        print("🚗 Creating PodcastListViewModel")
        podcastListViewModel = PodcastListViewModel()

        // Load data and setup interface
        print("🚗 Starting setupCarPlayInterface task")
        Task {
            await setupCarPlayInterface()
        }
    }

    @objc func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        print("🚗 CarPlay disconnected")
        self.interfaceController = nil
        self.podcastListViewModel = nil
        templateManager.clearArtworkCache()
    }

    // MARK: - Interface Setup

    @MainActor
    private func setupCarPlayInterface() async {
        print("🚗 setupCarPlayInterface started")
        guard let viewModel = podcastListViewModel else {
            print("🚗 ERROR: No viewModel!")
            return
        }

        // Load libraries and podcasts
        print("🚗 Loading libraries...")
        await viewModel.loadLibraries()
        print("🚗 Libraries loaded: \(viewModel.libraries.count)")

        // For now, select first library if available
        if let firstLibrary = viewModel.libraries.first {
            print("🚗 Loading podcasts for library: \(firstLibrary.name)")
            await viewModel.loadPodcasts(for: firstLibrary)
            print("🚗 Podcasts loaded: \(viewModel.podcasts.count)")
        }

        // Create templates
        print("🚗 Creating podcast list template...")
        let podcastsTemplate = createPodcastListTemplate()
        print("🚗 Creating now playing template...")
        let nowPlayingTemplate = templateManager.createNowPlayingTemplate()

        // Create tab bar with both templates
        print("🚗 Creating tab bar template...")
        let tabBarTemplate = templateManager.createTabBarTemplate(
            podcastsTemplate: podcastsTemplate,
            nowPlayingTemplate: nowPlayingTemplate
        )

        // Set as root template
        print("🚗 Setting root template...")
        interfaceController?.setRootTemplate(tabBarTemplate, animated: true) { success, error in
            if let error = error {
                print("🚗 ERROR: Failed to set root template: \(error)")
            } else {
                print("🚗 SUCCESS: CarPlay interface setup complete")
            }
        }
    }

    // MARK: - Podcast List

    private func createPodcastListTemplate() -> CPListTemplate {
        guard let viewModel = podcastListViewModel else {
            return CPListTemplate(title: "Podcasts", sections: [])
        }

        return templateManager.createPodcastListTemplate(
            podcasts: viewModel.podcasts,
            onSelectPodcast: { [weak self] podcast in
                self?.showEpisodeList(for: podcast)
            },
            onGenreFilter: { [weak self] in
                self?.showGenreFilter()
            },
            onSortOptions: { [weak self] in
                self?.showSortOptions()
            }
        )
    }

    private func refreshPodcastList() {
        guard let interfaceController = interfaceController else { return }

        // Find the current tab bar template
        if let tabBarTemplate = interfaceController.rootTemplate as? CPTabBarTemplate,
           let podcastsTemplate = tabBarTemplate.templates.first as? CPListTemplate {

            // Get the updated podcasts
            guard let viewModel = podcastListViewModel else { return }

            // Create new template with updated data
            let newTemplate = templateManager.createPodcastListTemplate(
                podcasts: viewModel.podcasts,
                onSelectPodcast: { [weak self] podcast in
                    self?.showEpisodeList(for: podcast)
                },
                onGenreFilter: { [weak self] in
                    self?.showGenreFilter()
                },
                onSortOptions: { [weak self] in
                    self?.showSortOptions()
                }
            )

            // Update the sections in place
            podcastsTemplate.updateSections(newTemplate.sections)
        }
    }

    // MARK: - Episode List

    private func showEpisodeList(for podcast: Podcast) {
        Task {
            // Load episodes
            let episodes = await loadEpisodes(for: podcast.id)

            // Create episode list template
            let episodeTemplate = templateManager.createEpisodeListTemplate(
                podcast: podcast,
                episodes: episodes,
                onSelectEpisode: { [weak self] episode in
                    self?.playEpisode(episode, from: podcast)
                }
            )

            // Push onto navigation stack
            interfaceController?.pushTemplate(episodeTemplate, animated: true) { success, error in
                if let error = error {
                    print("Failed to push episode template: \(error)")
                }
            }
        }
    }

    private func loadEpisodes(for podcastId: String) async -> [Episode] {
        do {
            return try await api.getEpisodes(podcastId: podcastId)
        } catch {
            print("Failed to load episodes: \(error)")
            return []
        }
    }

    // MARK: - Playback

    private func playEpisode(_ episode: Episode, from podcast: Podcast) {
        // Construct audio URL (similar to EpisodeDetailViewModel)
        guard let serverURL = api.serverURL else {
            print("Server URL not available")
            showErrorAlert(message: "Unable to play episode")
            return
        }

        // Get audio URL from enclosure
        let audioPath: String
        if let enclosureUrl = episode.enclosure?.url {
            audioPath = enclosureUrl
        } else {
            print("Audio file not available")
            showErrorAlert(message: "Unable to play episode")
            return
        }

        // If the path is already a full URL, use it directly
        let audioURLString: String
        if audioPath.hasPrefix("http://") || audioPath.hasPrefix("https://") {
            audioURLString = audioPath
        } else {
            // Otherwise, construct URL with server and add auth token
            guard let token = api.authToken else {
                print("Not authenticated")
                showErrorAlert(message: "Unable to play episode")
                return
            }
            audioURLString = "\(serverURL)\(audioPath)?token=\(token)"
        }

        guard let audioURL = URL(string: audioURLString) else {
            print("Invalid audio URL")
            showErrorAlert(message: "Unable to play episode")
            return
        }

        // Start playback
        audioPlayer.play(episode: episode, audioURL: audioURL, podcast: podcast)

        print("Playing episode: \(episode.displayTitle)")
    }

    // MARK: - Genre Filter

    private func showGenreFilter() {
        guard let viewModel = podcastListViewModel else { return }

        let actionSheet = templateManager.createGenreFilterActionSheet(
            availableGenres: viewModel.availableGenres,
            currentGenre: viewModel.selectedGenre,
            onSelectGenre: { [weak self] genre in
                self?.applyGenreFilter(genre)
            }
        )

        interfaceController?.presentTemplate(actionSheet, animated: true) { success, error in
            if let error = error {
                print("Failed to present genre filter: \(error)")
            }
        }
    }

    private func applyGenreFilter(_ genre: String?) {
        podcastListViewModel?.setGenreFilter(genre)
        refreshPodcastList()
    }

    // MARK: - Sort Options

    private func showSortOptions() {
        guard let viewModel = podcastListViewModel else { return }

        let actionSheet = templateManager.createSortOptionsActionSheet(
            currentSort: viewModel.sortOption,
            onSelectSort: { [weak self] sortOption in
                self?.applySortOption(sortOption)
            }
        )

        interfaceController?.presentTemplate(actionSheet, animated: true) { success, error in
            if let error = error {
                print("Failed to present sort options: \(error)")
            }
        }
    }

    private func applySortOption(_ sortOption: SortOption) {
        podcastListViewModel?.setSortOption(sortOption)
        refreshPodcastList()
    }

    // MARK: - Error Handling

    private func showErrorAlert(message: String) {
        let alert = templateManager.createErrorAlert(message: message)

        interfaceController?.presentTemplate(alert, animated: true) { success, error in
            if let error = error {
                print("Failed to present error alert: \(error)")
            }
        }
    }
}
