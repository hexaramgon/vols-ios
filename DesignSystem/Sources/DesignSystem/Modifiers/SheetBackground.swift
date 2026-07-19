//
//  SheetBackground.swift
//  Volspire
//
//  The single source of truth for slide-up sheet CHROME. Every sheet uses
//  `.sheetBackground()` so they match — change the look here to restyle them all.
//  Besides the frosted background it applies the whole standard triple the
//  sheets used to repeat by hand: dark colour scheme, drag indicator, and the
//  app-wide tap-to-dismiss-keyboard behaviour.
//

import SwiftUI

public extension View {
    /// The app-standard slide-up sheet chrome: dark frosted material background,
    /// forced dark scheme, a visible drag indicator (pass `dragIndicator: false`
    /// for sheets that hide it), and tap-to-dismiss-keyboard.
    func sheetBackground(dragIndicator: Bool = true) -> some View {
        tapToDismissKeyboard()
            .presentationBackground {
                Color.black.opacity(0.28).background(.regularMaterial)
            }
            .presentationDragIndicator(dragIndicator ? .visible : .hidden)
            .environment(\.colorScheme, .dark)
    }
}
