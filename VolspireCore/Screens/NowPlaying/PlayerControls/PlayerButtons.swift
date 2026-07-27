//
//  PlayerButtons.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct PlayerButtons: View {
    @Environment(PlayerController.self) var model

    /// Compact (minimized immersive video): slightly smaller icons + play circle.
    var compact: Bool = false

    private var sideSize: CGFloat { compact ? 22 : 26 }
    private var skipSize: IconSize { compact ? .xxl : .hero }
    /// Bright transport tint (matches the skip buttons) for the inactive state.
    private var opaque: Color { Color(Palette.PlayerCard.opaque) }
    private var playGlyphSize: IconSize { compact ? .xxl : .hero }
    private var playCircle: CGFloat { compact ? 56 : 72 }
    /// Compact IS the minimized/immersive state, where the blurred backdrop is
    /// gone and these glyphs sit on bare video. In the default player the blur
    /// behind them is enough, which is how they shipped.
    private var glyphShadow: PlayerOverlayShadow { compact ? .strong : .off }

    var body: some View {
        let switchDisabled = !model.commandProfile.isSwitchTrackEnabled

        // shuffle · skip-back · big white play circle · skip-forward · repeat —
        // spread evenly across the width.
        HStack(spacing: 0) {
            Button { model.toggleShuffle() } label: {
                LucideIcon(.shuffle, size: sideSize)
                    .foregroundStyle(model.isShuffleOn ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(opaque))
                    .playerOverlayShadow(glyphShadow)
                    // Declared-instant tint. Same value-scoped idiom as the action-row
                    // like/save icons (which declare a 0.18s ease) — owning the toggle's
                    // animation means no ambient transaction can leak in, while layout
                    // changes (resize/move when minimizing) still animate.
                    .animation(nil, value: model.isShuffleOn)
            }

            Spacer(minLength: 0)

            Button { model.onBackward() } label: {
                LucideIcon(.skipBack, skipSize)
                    .foregroundStyle(Color(Palette.PlayerCard.opaque))
                    .playerOverlayShadow(glyphShadow)
            }
            .disabled(switchDisabled)
            .opacity(switchDisabled ? 0.4 : 1)

            Spacer(minLength: 0)

            // Play/Pause — big white circle with a thick black glyph (the web's center button).
            // While the track is loading, the button is disabled + dimmed grey.
            Button { model.onPlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: playCircle, height: playCircle)
                        // Deliberately NOT `playerOverlayShadow()`: that's tuned
                        // for thin glyphs, and its tight near-black layer would
                        // draw a hard rim around a solid 56–72pt disc. This one
                        // reads as depth — deepened only on bare video, where
                        // the circle has no blur to separate it.
                        .shadow(color: .black.opacity(compact ? 0.45 : 0.25),
                                radius: compact ? 10 : 8, y: 4)
                    LucideIcon(model.state.isPlaying ? .pauseFill : .playFill, playGlyphSize)
                        .foregroundStyle(.black)
                        .offset(x: model.state.isPlaying ? 0 : 2) // nudge the play triangle to optical center
                        .contentTransition(.identity)
                        .animation(nil, value: model.state.isPlaying) // swap instantly, no animation
                }
                .opacity(model.isLoadingTrack ? 0.4 : 1)
            }
            // No dim/recolor while held — the white circle should stay put.
            .buttonStyle(NoHighlightButtonStyle())
            .disabled(model.isLoadingTrack)

            Spacer(minLength: 0)

            Button { model.onForward() } label: {
                LucideIcon(.skipForward, skipSize)
                    .foregroundStyle(Color(Palette.PlayerCard.opaque))
                    .playerOverlayShadow(glyphShadow)
            }
            .disabled(switchDisabled)
            .opacity(switchDisabled ? 0.4 : 1)

            Spacer(minLength: 0)

            Button { model.toggleRepeat() } label: {
                LucideIcon(.`repeat`, size: sideSize)
                    .foregroundStyle(model.isRepeatOn ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(opaque))
                    .playerOverlayShadow(glyphShadow)
                    // Declared-instant tint (see shuffle above).
                    .animation(nil, value: model.isRepeatOn)
            }
        }
        .buttonStyle(.plain)
    }
}


/// A button style that never changes appearance on press (no dim, no recolor,
/// no scale) — used for the play/pause circle so it stays static while held.
private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController()
    ZStack(alignment: .top) {
        PreviewBackground()
        VStack {
            Text("Header")
                .blendMode(.overlay)
            PlayerButtons()
            Text("Footer")
                .blendMode(.overlay)
        }
        .foregroundStyle(Color(Palette.PlayerCard.opaque))
    }
    .environment(playerController)
}
