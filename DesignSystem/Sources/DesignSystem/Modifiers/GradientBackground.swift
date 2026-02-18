//
//  GradientBackground.swift
//  Volspire
//
//

import SwiftUI

public struct GradientBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .background {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(white: 0.0), Color(white: 0.12)]
                        : [Color(white: 1.0), Color(white: 0.92)],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()
            }
    }
}

public extension View {
    func gradientBackground() -> some View {
        modifier(GradientBackground())
    }
}
