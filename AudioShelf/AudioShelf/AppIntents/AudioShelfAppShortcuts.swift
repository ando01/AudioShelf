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
                "Play latest podcast in \(.applicationName)",
                "Play newest episode in \(.applicationName)",
                "Start playing latest episode in \(.applicationName)"
            ],
            shortTitle: "Play Latest Episode",
            systemImageName: "play.circle.fill"
        )
    }
}
