//
//  AudioShelfApp.swift
//  AudioShelf
//
//  Created by Andrew Melton on 1/7/26.
//

import SwiftUI

@main
struct AudioShelfApp: App {
    @State private var isLoggedIn = AudioBookshelfAPI.shared.isLoggedIn
    private var audioPlayer = AudioPlayer.shared

    var body: some Scene {
        WindowGroup {
            RootView(isLoggedIn: $isLoggedIn, audioPlayer: audioPlayer)
        }
    }
}

struct RootView: View {
    @Binding var isLoggedIn: Bool
    @Bindable var audioPlayer: AudioPlayer
    @State private var isPlayerExpanded = false

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
    }
}

// MARK: - Floating Player with Drag Gestures

struct FloatingPlayerView: View {
    @Bindable var audioPlayer: AudioPlayer
    @Binding var isExpanded: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingPlayer = false
    @AppStorage("playerExpanded") private var persistedExpanded = false

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let miniPlayerHeight: CGFloat = 160
            let expandedHeight = screenHeight

            ZStack(alignment: .top) {
                if isExpanded {
                    ExpandedPlayerView(
                        audioPlayer: audioPlayer,
                        isExpanded: $isExpanded
                    )
                    .frame(height: expandedHeight)
                    .offset(y: max(0, dragOffset))
                } else {
                    MiniPlayerView(audioPlayer: audioPlayer)
                        .frame(height: miniPlayerHeight)
                        .offset(y: dragOffset)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDraggingPlayer = true
                        if isExpanded {
                            // Dragging down from expanded state
                            dragOffset = max(0, value.translation.height)
                        } else {
                            // Dragging up from mini state
                            dragOffset = min(0, value.translation.height)
                        }
                    }
                    .onEnded { value in
                        isDraggingPlayer = false
                        let threshold: CGFloat = 100

                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if isExpanded {
                                // If dragged down more than threshold, minimize
                                if dragOffset > threshold {
                                    isExpanded = false
                                    persistedExpanded = false
                                }
                                dragOffset = 0
                            } else {
                                // If dragged up more than threshold, expand
                                if dragOffset < -threshold {
                                    isExpanded = true
                                    persistedExpanded = true
                                }
                                dragOffset = 0
                            }
                        }
                    }
            )
            .onAppear {
                isExpanded = persistedExpanded
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Mini Player View

struct MiniPlayerView: View {
    @Bindable var audioPlayer: AudioPlayer
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            Divider()
                .padding(.top, 8)

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
                        .frame(width: 44, alignment: .trailing)

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

                    Text(formatTime(audioPlayer.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                }

                // Controls - centered play button with symmetric layout
                HStack(spacing: 0) {
                    // Left side - Skip backward
                    HStack {
                        Button {
                            audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                        }
                        Spacer()
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

                    // Right side - Speed and Skip forward
                    HStack(spacing: 16) {
                        Spacer()

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
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    // Podcast artwork placeholder
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 300, height: 300)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 80))
                                .foregroundStyle(.blue.opacity(0.5))
                        }
                        .padding(.top, 40)

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

                            Text(formatTime(audioPlayer.duration))
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
                        HStack {
                            Text("Speed:")
                                .foregroundStyle(.secondary)
                            Text("\(audioPlayer.playbackSpeed, specifier: "%.2g")×")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        .font(.headline)
                    }
                    .padding(.top, 16)

                    Spacer()
                }
            }
            .background(.regularMaterial)
        }
        .background(.regularMaterial)
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
