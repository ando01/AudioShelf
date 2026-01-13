//
//  AudioShelfAppShortcuts.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-12.
//

import Foundation
import AppIntents

struct AudioShelfAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayLatestEpisodeIntent(),
            phrases: [
                "Play latest episode in \(.applicationName)",
                "Play newest episode in \(.applicationName)",
                "Start playing in \(.applicationName)",
                "Play latest episode of \(\.$podcast) in \(.applicationName)",
                "Play newest episode of \(\.$podcast) in \(.applicationName)",
                "Play latest \(\.$podcast) in \(.applicationName)"
            ],
            shortTitle: "Play Latest Episode",
            systemImageName: "play.circle.fill"
        )
    }
}
