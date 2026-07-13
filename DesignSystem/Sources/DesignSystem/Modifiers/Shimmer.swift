//
//  Shimmer.swift
//  Volspire
//
//  Airbnb-style skeleton shimmer: a soft light band sweeps diagonally across
//  whatever it's applied to by masking the content with a moving gradient, so
//  the placeholder "bones" gently pulse-and-sweep instead of sitting flat.
//

import SwiftUI

public struct Shimmer: ViewModifier {
    private let active: Bool
    private let duration: Double
    @State private var phase: CGFloat = 0

    public init(active: Bool = true, duration: Double = 1.35) {
        self.active = active
        self.duration = duration
    }

    public func body(content: Content) -> some View {
        if active {
            content
                .mask(gradientMask)
                .onAppear {
                    phase = 0
                    // One runloop later: starting a repeatForever animation inside
                    // the same transaction as a nav-push insertion can attach it to
                    // the transition's geometry (the classic repeatForever leak),
                    // which jitters the push. After a hop the insertion has committed.
                    DispatchQueue.main.async {
                        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                            phase = 0.8
                        }
                    }
                }
        } else {
            content
        }
    }

    /// A diagonal band where the centre is fully opaque and the edges dim the
    /// content to ~40%. Sliding the band's location animates the sweep; the 3×
    /// scale pushes the band fully off-content at each end so the loop is
    /// seamless and stop locations stay within 0...1 (no clamping artifacts).
    private var gradientMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.4), location: phase),
                .init(color: .black, location: phase + 0.1),
                .init(color: .black.opacity(0.4), location: phase + 0.2),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .scaleEffect(3)
    }
}

public extension View {
    /// Sweeps a soft shimmer across the view — use on skeleton placeholders.
    func shimmering(active: Bool = true, duration: Double = 1.35) -> some View {
        modifier(Shimmer(active: active, duration: duration))
    }
}
