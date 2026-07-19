//
//  SheetBackground.swift
//  DesignSystem
//
//  The single source of truth for slide-up sheet backgrounds. Every sheet uses
//  `.sheetBackground()` so they match — change the look here to restyle them all.
//

import SwiftUI

public extension View {
    /// The app-standard slide-up sheet background — a dark frosted material.
    /// Also grants every sheet the app-wide tap-to-dismiss-keyboard behaviour.
    func sheetBackground() -> some View {
        tapToDismissKeyboard()
            .presentationBackground {
                Color.black.opacity(0.28).background(.regularMaterial)
            }
    }
}
