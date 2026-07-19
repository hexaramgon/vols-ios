//
//  EqualizerBars.swift
//  Volspire
//
//  The animated "playing" equalizer bars, parameterized by geometry — replaces
//  the two hand-rolled copies (Home's 5-bar / Profile's 3-bar). Loops via a
//  local @State flipped onAppear (per the repeatForever identity rule).
//

import SwiftUI

struct EqualizerBars: View {
    var heights: [CGFloat] = [12, 22, 9, 18, 14]
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var tint: Color = .white
    var isAnimating: Bool = true
    @State private var raised = false

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: barWidth, height: heights[i])
                    .scaleEffect(y: raised ? 1 : 0.4, anchor: .center)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.46 + Double(i) * 0.12).repeatForever(autoreverses: true)
                            : .default,
                        value: raised
                    )
            }
        }
        .onAppear { raised = true }
    }
}
