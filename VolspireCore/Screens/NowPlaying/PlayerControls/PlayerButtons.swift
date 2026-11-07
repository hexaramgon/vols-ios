//
//  PlayerButtons.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct PlayerButtons: View {
    @Environment(PlayerController.self) var model

    // The web player's transport (track-detail-bottom-bar.tsx): stroke
    // shuffle/repeat, filled skips, an outline play/pause glyph in a white
    // circle — sized up a touch from the web's 20/24 for the phone player.
    private let toggleSize: CGFloat = 26
    private let skipSize: CGFloat = 32
    private let playGlyphSize: CGFloat = 28
    private let playCircle: CGFloat = 64
    /// Shuffle / repeat sit in a frame as wide as the old 26pt glyphs, so the
    /// repeat button stays centred on the right-hand icon column.
    private let toggleColumn: CGFloat = 26
    /// The web's resting tier for every side control: white at 64%, applied
    /// to the finished glyph (element opacity) so a filled skip's rim and
    /// body don't composite into an outline.
    private let restingOpacity = 0.64

    var body: some View {
        let switchDisabled = !model.commandProfile.isSwitchTrackEnabled

        // shuffle · skip-back · white play circle · skip-forward · repeat —
        // spread evenly across the width.
        HStack(spacing: 0) {
            Button { Haptics.impact(); model.toggleShuffle() } label: {
                toggleGlyph(.shuffle, on: model.isShuffleOn)
            }

            Spacer(minLength: 0)

            Button { model.onBackward() } label: {
                skipGlyph(.skipBack, disabled: switchDisabled)
            }
            .disabled(switchDisabled)

            Spacer(minLength: 0)

            // Play/Pause — white circle with the outline glyph in black (the
            // web's centre button). While the track is loading, the button is
            // disabled + dimmed.
            Button { model.onPlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: playCircle, height: playCircle)
                        // Deliberately NOT `playerOverlayShadow()`: that's tuned
                        // for thin glyphs, and its tight near-black layer would
                        // draw a hard rim around a solid disc. This one reads as
                        // depth (the web's shadow-lg).
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    LucideIcon(model.state.isPlaying ? .pause : .play, size: playGlyphSize)
                        .foregroundStyle(.black)
                        .offset(x: model.state.isPlaying ? 0 : 2) // the web's ml-0.5 optical nudge
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
                skipGlyph(.skipForward, disabled: switchDisabled)
            }
            .disabled(switchDisabled)

            Spacer(minLength: 0)

            // Off → repeat all → repeat one (the ¹ glyph), like Spotify /
            // Apple Music.
            Button { Haptics.impact(); model.cycleRepeat() } label: {
                toggleGlyph(model.repeatMode == .one ? .repeat1 : .`repeat`, on: model.repeatMode != .off)
            }
            .accessibilityLabel(repeatLabel)
        }
        .buttonStyle(.plain)
    }

    private var repeatLabel: String {
        switch model.repeatMode {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }

    /// Shuffle / repeat: resting white at 64%, the accent at full when on.
    private func toggleGlyph(_ icon: LucideIcon.Name, on: Bool) -> some View {
        LucideIcon(icon, size: toggleSize)
            .foregroundStyle(on ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(Color.white))
            .opacity(on ? 1 : restingOpacity)
            .frame(width: toggleColumn, height: toggleColumn)
            .contentShape(.rect)
            // Declared-instant tint — owning the toggle's animation means no
            // ambient transaction can leak in, while layout changes
            // (resize/move when minimizing) still animate.
            .animation(nil, value: on)
    }

    /// Filled skip glyph: 64% at rest, the web's 25% when there's nothing to skip to.
    private func skipGlyph(_ icon: LucideIcon.Name, disabled: Bool) -> some View {
        LucideIcon(icon, size: skipSize)
            .foregroundStyle(.white)
            .opacity(disabled ? 0.25 : restingOpacity)
            .padding(8)
            .contentShape(.rect)
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
