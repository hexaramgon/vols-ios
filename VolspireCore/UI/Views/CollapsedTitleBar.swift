//
//  CollapsedTitleBar.swift
//  Volspire
//
//  Scroll-collapsed chrome for hero/detail pages: a solid vBar + hairline with
//  a centred title (and optional subtitle) that fades in as the hero scrolls
//  past. `ScrollFadeState` is the isolation trick (same as the profile / Home
//  headers): per-frame scroll writes land in an @Observable only this bar
//  reads, so scrolling never re-renders the page body. Never hit-testable —
//  the system toolbar's back/"…" buttons sit on top and must stay live.
//

import DesignSystem
import SwiftUI

/// Scroll-driven fade state — feed it from `.onScrollGeometryChange` via
/// `update(offsetY:)`; only views reading `opacity` re-render.
@Observable @MainActor
final class ScrollFadeState {
    private(set) var opacity: Double = 0

    /// Content offset where the fade begins.
    private let fadeStart: CGFloat
    /// Scroll distance over which the fade reaches fully opaque.
    private let fadeDistance: CGFloat

    init(fadeStart: CGFloat = 40, fadeDistance: CGFloat = 70) {
        self.fadeStart = fadeStart
        self.fadeDistance = fadeDistance
    }

    func update(offsetY: CGFloat) {
        let next = Double(min(1, max(0, (offsetY - fadeStart) / fadeDistance)))
        if next != opacity { opacity = next }
    }
}

/// Solid bar + centred title/subtitle that fade in as a page's hero scrolls
/// away, driven by a `ScrollFadeState`.
struct CollapsedTitleBar: View {
    let state: ScrollFadeState
    let title: String
    var subtitle: String? = nil

    var body: some View {
        Color.vBar
            .frame(height: ViewConst.safeAreaInsets.top + 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.vBorder).frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.appCalloutSemibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appCaption2Medium)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                    }
                }
                // Keep clear of the side toolbar buttons, like a system bar.
                .padding(.horizontal, 64)
                .frame(height: 44)
            }
            .opacity(state.opacity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}
