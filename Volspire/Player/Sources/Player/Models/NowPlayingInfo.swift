//
//  NowPlayingInfo.swift
//  Volspire
//
//

import MediaLibrary
import UIKit

struct NowPlayingInfo {
    let meta: MediaMeta
    let artwork: UIImage
    let isPlaying: Bool
    let queue: Queue?
    let progress: Progress?

    init(
        meta: MediaMeta,
        artwork: UIImage,
        isPlaying: Bool,
        queue: Queue? = nil,
        progress: Progress? = nil
    ) {
        self.meta = meta
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.queue = queue
        self.progress = progress
    }

    struct Queue {
        let index: Int
        let count: Int
    }

    struct Progress {
        let elapsedTime: TimeInterval
        let duration: TimeInterval
    }
}
