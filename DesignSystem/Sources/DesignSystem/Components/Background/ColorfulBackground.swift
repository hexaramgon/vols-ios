//
//  ColorfulBackground.swift
//  Volspire
//
//

import SwiftUI

public struct ColorfulBackground: View {
    @State var model = ColorfulBackgroundModel()
    let colors: [Color]

    public init(colors: [Color]) {
        self.colors = colors
    }

    public var body: some View {
        MulticolorGradient(
            points: model.points,
            animationUpdateHandler: model.onUpdate(animatedData:)
        )
        .onAppear {
            model.set(colors)
            model.onAppear()
        }
        .onChange(of: colors) {
            model.set(colors)
        }
    }
}

#Preview {
    ColorfulBackground(colors: [.pink, .indigo, .cyan])
        .ignoresSafeArea()
}
