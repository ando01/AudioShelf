//
//  TVVideoPlayerView.swift
//  AudioShelfTV
//
//  Created by Claude on 2026-02-04.
//

#if os(tvOS)
import AVKit
import SwiftUI

/// Full-screen video player for tvOS with native Siri Remote controls.
struct TVVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
#else
import AVKit
import SwiftUI

// iOS fallback (not used on iOS, but allows compilation if shared target includes this file)
struct TVVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
#endif
