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
    /// Effective playback speed (e.g. 1.0, 1.5). The system interpolates the
    /// scrubber from elapsed time + this rate, so it stays accurate between the
    /// (now infrequent) pushes — even at non-1× speed.
    let playbackRate: Double
    let queue: Queue?
    let progress: Progress?

    init(
        meta: MediaMeta,
        artwork: UIImage,
        isPlaying: Bool,
        playbackRate: Double = 1.0,
        queue: Queue? = nil,
        progress: Progress? = nil
    ) {
        self.meta = meta
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
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
