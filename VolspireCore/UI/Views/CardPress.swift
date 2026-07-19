//
//  CardPress.swift
//  Volspire
//
//  The shared card press-down effect (was re-rolled per screen as
//  LibraryPress / PlaylistsPress / the marketplace card style).
//

import SwiftUI

struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
