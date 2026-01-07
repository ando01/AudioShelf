//
//  Library.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

struct LibrariesResponse: Codable {
    let libraries: [Library]
}

struct Library: Codable, Identifiable {
    let id: String
    let name: String
    let mediaType: String

    var isPodcastLibrary: Bool {
        mediaType == "podcast"
    }
}
