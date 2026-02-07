# AudioShelf

A native iOS and tvOS client for [Audiobookshelf](https://www.audiobookshelf.org/) - the self-hosted audiobook and podcast server.

## Features

### Cross-Platform
- **iOS app** with full playback controls, CarPlay support, and background audio
- **tvOS app** optimized for Apple TV with focus-based navigation
- **Server-side progress sync** - start listening on one device, continue on another

### Library Management
- Browse podcasts from your Audiobookshelf library
- View episodes sorted by publish date (newest first)
- Filter podcasts by genre
- Sort podcasts by latest episode, title, or genre
- Cover art loading with caching

### Playback
- Stream audio and video podcasts
- Background audio playback on iOS
- Lock screen and Control Center controls
- Skip forward/backward (30 seconds)
- Playback speed control (0.5x - 2x)
- Sleep timer
- Resume from last position

### Progress Sync
- Bidirectional sync with Audiobookshelf server
- Automatic sync every 30 seconds during playback
- Immediate sync on pause/stop for seamless device switching
- Offline support - progress queued and synced when back online
- Conflict resolution - "most progress wins" strategy

### Offline Support
- Cached libraries, podcasts, and episodes for offline browsing
- Pending progress syncs persisted and retried on app launch

### CarPlay
- Browse podcasts and episodes
- Now Playing controls
- Genre filtering

## Architecture

### Services

| Service | Purpose |
|---------|---------|
| `AudioBookshelfAPI` | Handles all server communication (login, libraries, podcasts, episodes, progress) |
| `AudioPlayer` | AVPlayer-based audio/video playback with Now Playing integration |
| `ProgressSyncService` | Orchestrates progress sync between local storage and server |
| `PlaybackProgressService` | Local progress storage in UserDefaults |
| `OfflineDataCache` | Caches server data for offline access |

### Progress Sync Flow

```
AudioPlayer → ProgressSyncService → AudioBookshelfAPI (server)
                    ↓
             PlaybackProgressService (local UserDefaults)
```

- All saves go to local storage immediately for fast UI
- Server syncs are debounced (30 seconds) during playback
- Pause/stop triggers immediate server sync
- Failed syncs are queued and retried on next app launch

### API Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/login` | POST | Authentication |
| `/api/libraries` | GET | Fetch libraries |
| `/api/libraries/{id}/items` | GET | Fetch podcasts |
| `/api/items/{id}` | GET | Fetch podcast with episodes |
| `/api/items/{id}/cover` | GET | Fetch cover image |
| `/api/me/progress/{libraryItemId}/{episodeId}` | GET | Fetch episode progress |
| `/api/me/progress/{libraryItemId}/{episodeId}` | PATCH | Update episode progress |
| `/api/me/items-in-progress` | GET | Fetch all in-progress items |

## Requirements

- iOS 17.0+
- tvOS 17.0+
- Audiobookshelf server (self-hosted)

## Setup

1. Clone the repository
2. Open `AudioShelf.xcodeproj` in Xcode
3. Build and run on your device or simulator
4. Enter your Audiobookshelf server URL and credentials

## Project Structure

```
AudioShelf/
├── AudioShelf/                 # iOS app
│   ├── AudioShelfApp.swift     # App entry point
│   ├── Models/                 # Data models
│   │   ├── Podcast.swift
│   │   ├── Episode.swift
│   │   ├── Library.swift
│   │   ├── User.swift
│   │   └── PlaybackProgress.swift
│   ├── Services/               # Business logic
│   │   ├── AudioBookshelfAPI.swift
│   │   ├── AudioPlayer.swift
│   │   ├── ProgressSyncService.swift
│   │   ├── PlaybackProgressService.swift
│   │   └── OfflineDataCache.swift
│   ├── ViewModels/             # View models
│   │   ├── PodcastListViewModel.swift
│   │   └── EpisodeDetailViewModel.swift
│   ├── Views/                  # SwiftUI views
│   └── CarPlay/                # CarPlay support
│       └── CarPlaySceneDelegate.swift
│
├── AudioShelfTV/               # tvOS app
│   ├── AudioShelfTVApp.swift   # App entry point
│   ├── Views/
│   │   ├── TVContentView.swift
│   │   ├── TVLoginView.swift
│   │   └── TVEpisodeListView.swift
│   └── Assets.xcassets/        # tvOS assets including Top Shelf images
│
└── README.md
```

## Changelog

### February 2026

#### Progress Sync Implementation
- Added `ProgressSyncService` for bidirectional server sync
- Added progress API methods to `AudioBookshelfAPI`:
  - `updateProgress()` - PATCH to server
  - `getProgress()` - GET single episode progress
  - `getItemsInProgress()` - GET all in-progress items
- Modified `AudioPlayer` to sync progress on pause/stop
- Added offline queue for failed syncs with automatic retry
- Added conflict resolution (most progress wins)
- Sync on app launch for both iOS and tvOS

#### tvOS Improvements
- Fixed logout functionality (replaced non-functional Menu with alert-based buttons)
- Added separate Sort and Sign Out toolbar buttons
- Fixed Top Shelf Image Wide 2x asset (4640x1440)

#### CarPlay
- Added genre filtering to CarPlay interface

#### Playback Optimizations
- Reduced audio buffer for faster startup
- Added playback timing diagnostics
- Fixed race condition with server progress fetch and player readiness
- Fixed pause/stop to capture actual player time before syncing

### January 2026

#### Initial Release
- iOS app with Audiobookshelf authentication
- Library and podcast browsing
- Episode playback with AVPlayer
- Background audio and Now Playing controls
- Local progress storage
- Offline caching
- CarPlay support
- tvOS app with focus-based navigation

## License

This project is for personal use with your own Audiobookshelf server.

## Acknowledgments

- [Audiobookshelf](https://www.audiobookshelf.org/) - The excellent self-hosted audiobook and podcast server this app connects to
