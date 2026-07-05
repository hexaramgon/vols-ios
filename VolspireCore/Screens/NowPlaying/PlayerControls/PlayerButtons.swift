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

    @State private var isShuffled = false
    @State private var repeatMode = 0 // 0 = off, 1 = all, 2 = one

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
            Button { isShuffled.toggle() } label: {
                LucideIcon(.shuffle, size: sideSize)
                    .foregroundStyle(isShuffled ? Color.brand : opaque)
                    // Declared-instant tint. Same value-scoped idiom as the action-row
                    // like/save icons (which declare a 0.18s ease) — owning the toggle's
                    // animation means no ambient transaction can leak in, while layout
                    // changes (resize/move when minimizing) still animate.
                    .animation(nil, value: isShuffled)
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

            Button { repeatMode = (repeatMode + 1) % 3 } label: {
                LucideIcon(repeatMode == 2 ? .repeat1 : .`repeat`, size: sideSize)
                    .foregroundStyle(repeatMode > 0 ? Color.brand : opaque)
                    // Declared-instant tint + glyph swap (see shuffle above).
                    .animation(nil, value: repeatMode)
                    .compactChip(compact)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// In minimized (immersive) mode the side transport icons lose the frost behind
    /// them, so give each a small blurred circle so it stays visible over the video.
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
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
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
