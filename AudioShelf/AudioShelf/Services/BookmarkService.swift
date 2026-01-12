//
//  BookmarkService.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-12.
//

import Foundation

@Observable
class BookmarkService {
    static let shared = BookmarkService()

    private let userDefaults = UserDefaults.standard
    private let bookmarksKey = "bookmarks"

    private(set) var bookmarks: [Bookmark] = []

    private init() {
        loadBookmarks()
    }

    // MARK: - Public Methods

    func addBookmark(episodeId: String, timestamp: Double, note: String?) {
        let bookmark = Bookmark(episodeId: episodeId, timestamp: timestamp, note: note)
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func getBookmarks(for episodeId: String) -> [Bookmark] {
        return bookmarks
            .filter { $0.episodeId == episodeId }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func hasBookmarks(for episodeId: String) -> Bool {
        return bookmarks.contains { $0.episodeId == episodeId }
    }

    // MARK: - Private Methods

    private func saveBookmarks() {
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(encoded, forKey: bookmarksKey)
        }
    }

    private func loadBookmarks() {
        if let data = userDefaults.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
    }
}
