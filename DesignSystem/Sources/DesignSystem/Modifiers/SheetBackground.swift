//
//  SheetBackground.swift
//  Volspire
//
//  The single source of truth for slide-up sheet CHROME. Every sheet uses
//  `.sheetBackground()` so they match — change the look here to restyle them all.
//  Besides the frosted background it applies the whole standard set the
//  sheets used to repeat by hand: drag indicator and the app-wide
//  tap-to-dismiss-keyboard behaviour. Sheets THEME with the app (light/dark);
//  only sheets presented over the always-dark Now Playing pass `alwaysDark`.
//

import SwiftUI

public extension View {
    /// The app-standard slide-up sheet chrome: a themed frosted panel
    /// (`vCardSolid`-toned in light, the dark frosted material in dark), a
    /// visible drag indicator (pass `dragIndicator: false` for sheets that hide
    /// it), and tap-to-dismiss-keyboard. `alwaysDark: true` pins the sheet to
    /// the dark scheme — for sheets presented from the full-screen player.
    func sheetBackground(dragIndicator: Bool = true, alwaysDark: Bool = false) -> some View {
        tapToDismissKeyboard()
            .presentationBackground {
                SheetChromeBackground().alwaysDark(alwaysDark)
            }
            .presentationDragIndicator(dragIndicator ? .visible : .hidden)
            .alwaysDark(alwaysDark)
    }

    /// Pins this SUBTREE to the dark scheme (`.environment(\.colorScheme, .dark)`)
    /// — for content that stays dark in light mode (Now Playing, the profile
    /// banner hero, image cropper, video). Never use `.preferredColorScheme`
    /// for this: it propagates up to the window and forces the whole app.
    @ViewBuilder
    func alwaysDark(_ enabled: Bool = true) -> some View {
        if enabled {
            environment(\.colorScheme, .dark)
        } else {
            self
        }
    }
}

/// The frosted sheet panel: in dark, a black tint over `.regularMaterial`
/// (the original look); in light, an opaque-ish `vCardSolid` wash over it.
private struct SheetChromeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark ? Color.black.opacity(0.28) : Color.vCardSolid.opacity(0.85))
            .background(.regularMaterial)
    }
}
