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
        return [
            AppShortcut(
                intent: PlayLatestFromDefaultIntent(),
                phrases: [
                    "Play latest episode in \(.applicationName)",
                    "Play newest episode in \(.applicationName)",
                    "Start playing in \(.applicationName)"
                ],
                shortTitle: "Play Latest Episode",
                systemImageName: "play.circle.fill"
            )
        ]
    }
}
