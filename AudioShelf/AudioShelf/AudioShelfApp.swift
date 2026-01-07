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

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                PodcastListView(isLoggedIn: $isLoggedIn)
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
    }
}
