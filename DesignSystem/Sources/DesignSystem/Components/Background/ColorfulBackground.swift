//
//  ColorfulBackground.swift
//  Volspire
//
//

import SwiftUI

public struct ColorfulBackground: View {
    @State var model = ColorfulBackgroundModel()
    let colors: [Color]
    /// When false the gradient freezes (no per-frame Metal redraw). Pass the
    /// player's expanded state so it only animates while actually on screen.
    var isAnimating: Bool

    public init(colors: [Color], isAnimating: Bool = true) {
        self.colors = colors
        self.isAnimating = isAnimating
    }

    public var body: some View {
        MulticolorGradient(
            points: model.points,
            animationUpdateHandler: model.onUpdate(animatedData:)
        )
        .onAppear {
            model.set(colors)
            model.onAppear()
            model.setAnimating(isAnimating)
        }
        .onChange(of: colors) {
            model.set(colors)
        }
        .onChange(of: isAnimating) { _, active in
            model.setAnimating(active)
        }
    }
}

#Preview {
    ColorfulBackground(colors: [.pink, .indigo, .cyan])
        .ignoresSafeArea()
}
