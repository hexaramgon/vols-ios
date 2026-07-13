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

    var body: some View {
        let switchDisabled = !model.commandProfile.isSwitchTrackEnabled

        // shuffle · skip-back · big white play circle · skip-forward · repeat —
        // spread evenly across the width.
        HStack(spacing: 0) {
            Button { model.toggleShuffle() } label: {
                LucideIcon(.shuffle, size: sideSize)
                    .foregroundStyle(model.isShuffleOn ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(opaque))
                    // Declared-instant tint. Same value-scoped idiom as the action-row
                    // like/save icons (which declare a 0.18s ease) — owning the toggle's
                    // animation means no ambient transaction can leak in, while layout
                    // changes (resize/move when minimizing) still animate.
                    .animation(nil, value: model.isShuffleOn)
                    .compactChip(compact)
            }

            Spacer(minLength: 0)

            Button { model.onBackward() } label: {
                LucideIcon(.skipBack, skipSize)
                    .foregroundStyle(Color(Palette.PlayerCard.opaque))
                    .compactChip(compact)
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
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
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
                    .compactChip(compact)
            }
            .disabled(switchDisabled)
            .opacity(switchDisabled ? 0.4 : 1)

            Spacer(minLength: 0)

            Button { model.toggleRepeat() } label: {
                LucideIcon(.`repeat`, size: sideSize)
                    .foregroundStyle(model.isRepeatOn ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(opaque))
                    // Declared-instant tint (see shuffle above).
                    .animation(nil, value: model.isRepeatOn)
                    .compactChip(compact)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// In minimized (immersive) mode the side transport icons lose the frost behind
    /// them, so give each a small darkened circle so it stays visible over the video.
    func compactChip(_ active: Bool) -> some View {
        modifier(CompactChip(active: active))
    }
}

private struct CompactChip: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .padding(active ? 10 : 0)
            .background(
                // A plain translucent scrim, not a material: five per-button
                // backdrop blurs over live video each cost a blur pass every
                // frame, and at this size the darkened look reads the same.
                Circle()
                    .fill(.black.opacity(0.35))
                    .opacity(active ? 1 : 0)
            )
    }
}

/// A button style that never changes appearance on press (no dim, no recolor,
/// no scale) — used for the play/pause circle so it stays static while held.
private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension PlayerButtonConfig {
    static var expandedPlayer: Self {
        Self(
            labelColor: .init(Palette.PlayerCard.opaque),
            tint: .init(Palette.PlayerCard.translucent.withAlphaComponent(0.3)),
            pressedColor: .init(Palette.PlayerCard.opaque),
            disabledColor: .init(Palette.PlayerCard.translucent)
        )
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
