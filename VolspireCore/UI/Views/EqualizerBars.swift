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
    var tint: Color = .vText
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
        // Paused (`isAnimating` false) settles static. Callers must
        // `.id(isAnimating)` so a running loop is torn down on pause.
        .onAppear { raised = true }
    }
}

// MARK: - On the cover

extension View {
    /// The playing row's marker, ON its cover: a dark tint with white bars
    /// (looping while `playing`, still when paused). Clipped to the cover's
    /// corners; nothing when the row isn't the loaded track.
    func playingCoverOverlay(active: Bool, playing: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if active {
                ZStack {
                    Color.vShade.opacity(0.45)
                    // `.id(playing)` tears the repeatForever down on pause.
                    EqualizerBars(heights: [7, 13, 9], barWidth: 2.5, spacing: 2, tint: .white, isAnimating: playing)
                        .id(playing)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
    }
}
