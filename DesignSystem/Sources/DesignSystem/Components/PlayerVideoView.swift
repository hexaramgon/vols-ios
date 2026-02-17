//
//  PlayerVideoView.swift
//  DesignSystem
//

import AVFoundation
import SwiftUI

/// A SwiftUI view that renders the video output of an `AVPlayer` using `AVPlayerLayer`.
/// This does NOT create its own player — it simply attaches to an existing one,
/// so audio and video stay perfectly in sync (same player instance).
public struct PlayerVideoView: UIViewRepresentable {
    public let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

/// A UIView backed by `AVPlayerLayer` so it renders video frames.
public final class PlayerLayerUIView: UIView {
    override public class var layerClass: AnyClass { AVPlayerLayer.self }
    public var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
