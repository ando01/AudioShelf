//
//  AudioShelfTVApp.swift
//  AudioShelfTV
//
//  Created by Andrew Melton on 2/4/26.
//

import SwiftUI

@main
struct AudioShelfTVApp: App {
    @State private var isLoggedIn = AudioBookshelfAPI.shared.isLoggedIn
    private var audioPlayer = AudioPlayer.shared

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                TVContentView(isLoggedIn: $isLoggedIn, audioPlayer: audioPlayer)
                    .task {
                        await ProgressSyncService.shared.syncAllFromServer()
                    }
            } else {
                TVLoginView(isLoggedIn: $isLoggedIn)
            }
        }
    }
}
