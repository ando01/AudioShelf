//
//  OpenAudioShelfIntent.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-12.
//

import Foundation
import AppIntents

struct OpenAudioShelfIntent: AppIntent {
    static var title: LocalizedStringResource = "Open AudioShelf"

    static var description = IntentDescription("Opens the AudioShelf app")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
