//
//  MainTabView.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import SwiftUI

struct MainTabView: View {
    @Binding var isLoggedIn: Bool
    var audioPlayer: AudioPlayer

    var body: some View {
        TabView {
            HomeView(audioPlayer: audioPlayer)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            PodcastListView(isLoggedIn: $isLoggedIn, audioPlayer: audioPlayer)
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            PodcastSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            SettingsView(isLoggedIn: $isLoggedIn)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    MainTabView(isLoggedIn: .constant(true), audioPlayer: AudioPlayer.shared)
}
