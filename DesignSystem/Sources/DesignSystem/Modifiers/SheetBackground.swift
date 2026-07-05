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
    func sheetBackground() -> some View {
        presentationBackground {
            Color.black.opacity(0.28).background(.regularMaterial)
        }
    }
}
