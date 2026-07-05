//
//  GradientBackground.swift
//  Volspire
//
//

import SwiftUI

public struct GradientBackground: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background {
                Color.appBase
                    .ignoresSafeArea()
            }
    }
}

public extension View {
    func gradientBackground() -> some View {
        modifier(GradientBackground())
    }
}
