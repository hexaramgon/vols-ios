//
//  KFImage+Downsample.swift
//  Volspire
//
//  Shared image-loading optimisation for raw `KFImage` usages (avatars, banners)
//  that don't go through `ArtworkView`. Decodes the remote image at its on-screen
//  size instead of full-resolution, and keeps the original cached so a prefetched
//  (un-processed) copy is reused — no second network fetch per display size.
//

import Kingfisher
import SwiftUI

public extension KFImage {
    /// Downsamples to `side` points (×screen scale) and caches the original.
    /// Use the displayed point size of the image; an oversized value just wastes
    /// a little memory, an undersized one softens it — so pass the real frame.
    ///
    /// `fade` crossfades in on async load (cached/prefetched images appear
    /// instantly). Pass `0` for non-square `.fill` images (e.g. a banner) where the
    /// built-in transition scales the image in — fade those with a plain `.opacity`
    /// at the call site instead so nothing stretches.
    func downsampled(to side: CGFloat, fade: TimeInterval = 0.25) -> KFImage {
        let px = max(1, side) * UIScreen.main.scale
        let base = setProcessor(DownsamplingImageProcessor(size: CGSize(width: px, height: px)))
            .cacheOriginalImage()
        // fade <= 0 must mean NO transition at all — `.fade(duration: 0)` still
        // configures a transition, which can animate the swap.
        return fade > 0 ? base.fade(duration: fade) : base
    }
}
