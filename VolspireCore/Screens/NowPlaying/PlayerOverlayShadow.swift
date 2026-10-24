//
//  PlayerOverlayShadow.swift
//  Volspire
//
//  The player's legibility shadow for white type and glyphs over artwork or
//  video — one fixed structure whose strength varies, switched on only while
//  a video plays (`playerOverlayShadowsEnabled`).
//

import SwiftUI

/// How hard `playerOverlayShadow()` works, which depends on what's behind the
/// element. The minimized/immersive transport sits on BARE video; the default
/// player keeps a blurred backdrop that already does most of the separating.
enum PlayerOverlayShadow {
    /// On bare video, body size or larger — title, artist, transport glyphs.
    case strong
    /// On bare video, small type (the scrubber's time labels). `.strong`'s tight
    /// layer visibly fattens glyphs at that size — it read as a bolder weight
    /// rather than a shadow — so this is one soft pool with no hard edge.
    case light
    /// Over the blurred player: the long-standing gentle shadow. Enough to keep
    /// white text off a busy backdrop without darkening the whole panel.
    case subtle
    /// No shadow — the blur behind it is doing the work.
    case off
}

extension View {
    /// Dark drop shadow so white content stays legible over video or artwork.
    /// Shared by everything that floats over the player surface. Applied
    /// per-element (not to a whole panel) so white-backed pieces — the tag
    /// chips, the play circle — are left untouched.
    ///
    /// `.strong` is two layers rather than one: a tight, near-opaque shadow
    /// hugging the glyphs gives the letterforms a hard edge, and a wide soft one
    /// pools darkness behind the whole line. A single shadow can only do one of
    /// those — pushing one radius far enough to darken the backdrop turns the
    /// text into a grey halo, which is why the description washed out over
    /// bright artwork at radius 3.
    func playerOverlayShadow(_ weight: PlayerOverlayShadow = .strong) -> some View {
        modifier(PlayerOverlayShadowModifier(weight: weight))
    }
}

extension EnvironmentValues {
    /// Whether the player's text/glyph drop shadows are on. RegularNowPlaying
    /// turns them on only while a video plays (white over moving footage);
    /// over the album-tint backdrop the type sits clean, like the rest of the app.
    @Entry var playerOverlayShadowsEnabled = true
}

private struct PlayerOverlayShadowModifier: ViewModifier {
    let weight: PlayerOverlayShadow
    @Environment(\.playerOverlayShadowsEnabled) private var enabled

    /// One fixed structure (two shadow layers) for every weight — only the
    /// values change. A `switch` over different modifier chains gave each
    /// weight its own view identity, so flipping weight (the immersive
    /// minimize) REPLACED the title, scrubber and transport with crossfading
    /// copies instead of letting them glide to their new spot.
    func body(content: Content) -> some View {
        let (tight, wide) = layers(enabled ? weight : .off)
        content
            .shadow(color: .black.opacity(tight.opacity), radius: tight.radius, y: tight.y)
            .shadow(color: .black.opacity(wide.opacity), radius: wide.radius)
    }

    private typealias Layer = (opacity: Double, radius: CGFloat, y: CGFloat)

    private func layers(_ weight: PlayerOverlayShadow) -> (Layer, Layer) {
        let none: Layer = (0, 0, 0)
        switch weight {
        case .strong: return ((0.75, 2, 1), (0.45, 8, 0))
        case .light: return ((0.5, 4, 1), none)
        case .subtle: return ((0.55, 3, 1), none)
        case .off: return (none, none)
        }
    }
}
