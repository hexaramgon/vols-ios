//
//  ArtworkView.swift
//  Volspire
//
//

import AVFoundation
import Kingfisher
import SwiftUI

public struct ArtworkView: View {
    let artwork: Artwork
    let cornerRadius: CGFloat
    var background: Color
    /// When true, video keeps its native aspect ratio centered within the square
    /// (letterboxed) instead of cropping to fill.
    var videoAspectFit: Bool

    /// The view's measured side length (points, quantized) used to downsample
    /// remote covers to their display size instead of decoding them full-res —
    /// the difference between ~1.5MB and ~35MB of memory per cover.
    @State private var measuredSide: CGFloat = 0

    public init(_ artwork: Artwork, cornerRadius: CGFloat = 8, background: Color = Color(.palette.artworkBackground), videoAspectFit: Bool = false) {
        self.artwork = artwork
        self.cornerRadius = cornerRadius
        self.background = background
        self.videoAspectFit = videoAspectFit
    }

    public var body: some View {
        let border = UIScreen.hairlineWidth
        ZStack {
            if !isAspectFitVideo {
                background
                    .aspectRatio(contentMode: .fit)
            }
            switch artwork {
            case let .placeholder(name):
                Image(lucide: .radio)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .aspectRatio(1.0, contentMode: .fit)
                    .scaleEffect(0.6)
                    .foregroundStyle(Color.iconSecondary)

            case let .webImage(url):
                KFImage.url(url)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: targetPx, height: targetPx)))
                    // Keep the original cached too, so a prefetched (un-processed)
                    // cover is reused here and downsampled from disk — no second
                    // network fetch when the cell scrolls in.
                    .cacheOriginalImage()
                    // Crossfade in when loaded from network/disk; cached (and
                    // prefetched) covers still appear instantly with no fade.
                    .fade(duration: 0.25)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .aspectRatio(1.0, contentMode: .fit)

            case .album:
                Image(lucide: .listVideo)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .aspectRatio(1.0, contentMode: .fit)
                    .scaleEffect(0.9)
                    .foregroundStyle(Color.iconSecondary)

            case let .videoPlayer(player):
                if videoAspectFit {
                    // Fill the (possibly non-square) container; resizeAspect keeps the
                    // video's native ratio centered within it — no cropping, no box.
                    PlayerVideoView(player: player, gravity: .resizeAspect)
                } else {
                    PlayerVideoView(player: player)
                        .aspectRatio(1.0, contentMode: .fill)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(proxy.size.width, proxy.size.height)
        } action: { side in
            // Quantize to 80pt steps so the downsample target (and its cache key)
            // stays stable across minor layout changes — no repeated re-decoding.
            let stepped = max(80, (side / 80).rounded(.up) * 80)
            if abs(stepped - measuredSide) > 1 { measuredSide = stepped }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            // No cover box for an aspect-fit video — show just the video, letting the
            // player's own background fill the space around it.
            if !isAspectFitVideo {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .inset(by: border / 2)
                    .stroke(Color(.palette.artworkBorder), lineWidth: border)
            }
        }
    }

    /// Target decode size in pixels: the measured side (or a sane default before
    /// the first layout pass) times the screen scale, hard-capped so even the
    /// full-screen now-playing cover never decodes more than it can display.
    private var targetPx: CGFloat {
        let side = measuredSide > 0 ? measuredSide : 200
        return min(side * UIScreen.main.scale, 1400)
    }

    /// A video rendered at its native aspect ratio — no square cover background/border.
    private var isAspectFitVideo: Bool {
        if videoAspectFit, case .videoPlayer = artwork { return true }
        return false
    }
}

#Preview {
    VStack {
        ArtworkView(
            .placeholder(name: "Sample")
        )
        ArtworkView(.placeholder(name: "Rock"))
        ArtworkView(.placeholder())
        ArtworkView(.album)
    }
}
