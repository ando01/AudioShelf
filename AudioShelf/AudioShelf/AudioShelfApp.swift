//
//  AudioShelfApp.swift
//  AudioShelf
//
//  Created by Andrew Melton on 1/7/26.
//

import SwiftUI
import AVFoundation
import UIKit
import CarPlay

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Check if this is a CarPlay scene
        if connectingSceneSession.role == .carTemplateApplication {
            let sceneConfig = UISceneConfiguration(
                name: "CarPlay Configuration",
                sessionRole: connectingSceneSession.role
            )
            sceneConfig.delegateClass = CarPlaySceneDelegate.self
            return sceneConfig
        }

        // Default configuration for regular app scenes
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}

@main
struct AudioShelfApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isLoggedIn = AudioBookshelfAPI.shared.isLoggedIn
    @Environment(\.scenePhase) private var scenePhase
    private var audioPlayer = AudioPlayer.shared

    var body: some Scene {
        WindowGroup {
            RootView(isLoggedIn: $isLoggedIn, audioPlayer: audioPlayer)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Reactivate audio session when app becomes active
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to reactivate audio session: \(error)")
                }
            }
        }
    }
}

struct RootView: View {
    @Binding var isLoggedIn: Bool
    @Bindable var audioPlayer: AudioPlayer
    @State private var isPlayerExpanded = false
    @State private var lastEpisodeId: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            if isLoggedIn {
                PodcastListView(isLoggedIn: $isLoggedIn, audioPlayer: audioPlayer)
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }

            // Persistent floating player at bottom
            if audioPlayer.currentEpisode != nil {
                FloatingPlayerView(
                    audioPlayer: audioPlayer,
                    isExpanded: $isPlayerExpanded
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: audioPlayer.currentEpisode != nil)
        .onChange(of: audioPlayer.currentEpisode?.id) { oldId, newId in
            // When a new episode starts playing, minimize the player
            if newId != nil && newId != lastEpisodeId {
                isPlayerExpanded = false
                lastEpisodeId = newId
            }
        }
    }
}

// MARK: - Floating Player with Drag Gestures

struct FloatingPlayerView: View {
    @Bindable var audioPlayer: AudioPlayer
    @Binding var isExpanded: Bool
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                ExpandedPlayerView(
                    audioPlayer: audioPlayer,
                    isExpanded: $isExpanded,
                    dragOffset: $dragOffset
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                Spacer()
                MiniPlayerView(
                    audioPlayer: audioPlayer,
                    isExpanded: $isExpanded,
                    dragOffset: $dragOffset
                )
            }
        }
    }
}

// MARK: - Mini Player View

struct MiniPlayerView: View {
    @Bindable var audioPlayer: AudioPlayer
    @Binding var isExpanded: Bool
    @Binding var dragOffset: CGFloat
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var showBookmarkDialog = false
    @State private var bookmarkNote = ""
    private let bookmarkService = BookmarkService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle - only this area is draggable
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only allow dragging up
                            dragOffset = min(0, value.translation.height)
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 100
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if dragOffset < -threshold {
                                    isExpanded = true
                                }
                                dragOffset = 0
                            }
                        }
                )

            Divider()

            VStack(spacing: 8) {
                // Episode info
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let episode = audioPlayer.currentEpisode {
                            Text(episode.displayTitle)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        if let podcast = audioPlayer.currentPodcast {
                            Text(podcast.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }

                // Progress bar (draggable slider) with time labels
                HStack(spacing: 8) {
                    Text(formatTime(isDragging ? dragValue : audioPlayer.currentTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 50, alignment: .trailing)

                    Slider(
                        value: isDragging ? $dragValue : Binding(
                            get: { audioPlayer.currentTime },
                            set: { _ in }
                        ),
                        in: 0...max(audioPlayer.duration, 1)
                    ) { isEditing in
                        isDragging = isEditing
                        if !isEditing {
                            audioPlayer.seek(to: dragValue)
                        } else {
                            dragValue = audioPlayer.currentTime
                        }
                    }
                    .tint(.blue)

                    Text(formatTime(audioPlayer.duration - (isDragging ? dragValue : audioPlayer.currentTime)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 50, alignment: .leading)
                }

                // Controls - centered play button with symmetric layout
                HStack(spacing: 0) {
                    // Left side - Skip backward and Bookmark
                    HStack(spacing: 0) {
                        Button {
                            audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                        }

                        Spacer()

                        // Bookmark button
                        Button {
                            showBookmarkDialog = true
                        } label: {
                            Image(systemName: "bookmark")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Center - Play/Pause button
                    Button {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.resume()
                        }
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 70)
                    .padding(.horizontal, 12)

                    // Right side - Speed and Skip forward
                    HStack(spacing: 0) {
                        // Playback speed
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                                Button {
                                    audioPlayer.setPlaybackSpeed(Float(speed))
                                } label: {
                                    HStack {
                                        Text("\(speed, specifier: "%.2g")×")
                                        if audioPlayer.playbackSpeed == Float(speed) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text("\(audioPlayer.playbackSpeed, specifier: "%.2g")×")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                                .frame(minWidth: 36)
                        }

                        Spacer()

                        // Skip forward 30s
                        Button {
                            let newTime = audioPlayer.currentTime + 30
                            let seekTime = audioPlayer.duration > 0
                                ? min(audioPlayer.duration, newTime)
                                : newTime
                            audioPlayer.seek(to: seekTime)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.title2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
        .offset(y: dragOffset)
        .alert("Add Bookmark", isPresented: $showBookmarkDialog) {
            TextField("Note (optional)", text: $bookmarkNote)
            Button("Cancel", role: .cancel) {
                bookmarkNote = ""
            }
            Button("Save") {
                if let episode = audioPlayer.currentEpisode {
                    let note = bookmarkNote.isEmpty ? nil : bookmarkNote
                    bookmarkService.addBookmark(
                        episodeId: episode.id,
                        timestamp: audioPlayer.currentTime,
                        note: note
                    )
                    bookmarkNote = ""
                }
            }
        } message: {
            Text("Save bookmark at \(formatTime(audioPlayer.currentTime))")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Expanded Player View

struct ExpandedPlayerView: View {
    @Bindable var audioPlayer: AudioPlayer
    @Binding var isExpanded: Bool
    @Binding var dragOffset: CGFloat
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var coverImage: UIImage?
    @State private var showBookmarkDialog = false
    @State private var bookmarkNote = ""
    @State private var selectedTab = 0
    @Environment(\.colorScheme) private var colorScheme
    private let bookmarkService = BookmarkService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle area - always visible at top
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging down
                        dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 100
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if dragOffset > threshold {
                                isExpanded = false
                            }
                            dragOffset = 0
                        }
                    }
            )

            // TabView for swipeable pages
            TabView(selection: $selectedTab) {
                // Page 1: Player Controls
                ScrollView {
                    VStack(spacing: 24) {
                        // Podcast artwork
                    Group {
                        if let image = coverImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 300, height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 300, height: 300)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 80))
                                        .foregroundStyle(.blue.opacity(0.5))
                                }
                        }
                    }
                    .padding(.top, 40)
                    .task {
                        await loadCoverArt()
                    }
                    .onChange(of: audioPlayer.currentPodcast?.id) {
                        Task {
                            await loadCoverArt()
                        }
                    }

                    // Episode info
                    VStack(spacing: 8) {
                        if let episode = audioPlayer.currentEpisode {
                            Text(episode.displayTitle)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                        }
                        if let podcast = audioPlayer.currentPodcast {
                            Text(podcast.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal)

                    // Progress slider with time labels
                    VStack(spacing: 8) {
                        Slider(
                            value: isDragging ? $dragValue : Binding(
                                get: { audioPlayer.currentTime },
                                set: { _ in }
                            ),
                            in: 0...max(audioPlayer.duration, 1)
                        ) { isEditing in
                            isDragging = isEditing
                            if !isEditing {
                                audioPlayer.seek(to: dragValue)
                            } else {
                                dragValue = audioPlayer.currentTime
                            }
                        }
                        .tint(.blue)

                        HStack {
                            Text(formatTime(isDragging ? dragValue : audioPlayer.currentTime))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Spacer()

                            Text(formatTime(audioPlayer.duration - (isDragging ? dragValue : audioPlayer.currentTime)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 32)

                    // Playback controls
                    HStack(spacing: 40) {
                        // Skip backward
                        Button {
                            audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 36))
                        }

                        // Play/Pause
                        Button {
                            if audioPlayer.isPlaying {
                                audioPlayer.pause()
                            } else {
                                audioPlayer.resume()
                            }
                        } label: {
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.blue)
                        }

                        // Skip forward
                        Button {
                            let newTime = audioPlayer.currentTime + 30
                            let seekTime = audioPlayer.duration > 0
                                ? min(audioPlayer.duration, newTime)
                                : newTime
                            audioPlayer.seek(to: seekTime)
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.system(size: 36))
                        }
                    }

                    // Playback speed and bookmark
                    HStack(spacing: 24) {
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                                Button {
                                    audioPlayer.setPlaybackSpeed(Float(speed))
                                } label: {
                                    HStack {
                                        Text("\(speed, specifier: "%.2g")×")
                                        if audioPlayer.playbackSpeed == Float(speed) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Speed:")
                                    .foregroundStyle(.secondary)
                                Text("\(audioPlayer.playbackSpeed, specifier: "%.2g")×")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                            .font(.headline)
                        }

                        // Bookmark button
                        Button {
                            showBookmarkDialog = true
                        } label: {
                            HStack {
                                Image(systemName: "bookmark")
                                Text("Bookmark")
                            }
                            .font(.headline)
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.top, 16)

                    Spacer()
                }
            }
            .tag(0)

            // Page 2: Episode Details
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let episode = audioPlayer.currentEpisode {
                        // Episode title
                        Text(episode.displayTitle)
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.top, 20)

                        // Podcast name
                        if let podcast = audioPlayer.currentPodcast {
                            Text(podcast.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        // Published date and duration
                        HStack {
                            Text(episode.formattedPublishedDate)
                                .font(.subheadline)
                                .foregroundStyle(.blue)

                            if episode.duration != nil {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(episode.formattedDuration)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 8)

                        Divider()

                        // Episode description with HTML formatting
                        if let description = episode.description, !description.isEmpty {
                            Text(description.htmlToAttributedString(colorScheme: colorScheme))
                                .font(.system(size: 18))
                                .lineSpacing(6)
                                .textSelection(.enabled)
                                .tint(.blue)
                        } else {
                            Text("No description available")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(.regularMaterial)
        .offset(y: dragOffset)
        .alert("Add Bookmark", isPresented: $showBookmarkDialog) {
            TextField("Note (optional)", text: $bookmarkNote)
            Button("Cancel", role: .cancel) {
                bookmarkNote = ""
            }
            Button("Save") {
                if let episode = audioPlayer.currentEpisode {
                    let note = bookmarkNote.isEmpty ? nil : bookmarkNote
                    bookmarkService.addBookmark(
                        episodeId: episode.id,
                        timestamp: audioPlayer.currentTime,
                        note: note
                    )
                    bookmarkNote = ""
                }
            }
        } message: {
            Text("Save bookmark at \(formatTime(audioPlayer.currentTime))")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func loadCoverArt() async {
        guard let podcast = audioPlayer.currentPodcast,
              let coverURL = AudioBookshelfAPI.shared.getCoverImageURL(for: podcast) else {
            coverImage = nil
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: coverURL)
            if let image = UIImage(data: data) {
                coverImage = image
            }
        } catch {
            print("Failed to load cover art: \(error)")
            coverImage = nil
        }
    }
}
