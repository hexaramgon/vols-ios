//
//  RefreshChip.swift
//  Volspire
//
//  The floating pull-to-refresh indicator for screens whose fixed, overlaid
//  header hides the system spinner (it anchors at the scroll view's very top,
//  underneath the header). Use the `refreshChip(_:topInset:)` modifier on the
//  screen's container with an "is refreshing" flag and the header's height —
//  don't hand-roll per-screen spinners.
//

import SwiftUI

/// The refresh indicator, styled to read exactly like the NATIVE pull spinner
/// (screens whose headers sit above the scroll — Inbox, Library, Marketplace —
/// show the system one; this keeps overlaid-header screens looking the same).
/// The soft shadow is the only extra: this one floats over content.
public struct RefreshChip: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .tint(.white)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
    }
}

public extension View {
    /// Floats a `RefreshChip` centered `topInset` points from this view's top
    /// while `active` — fade+scale in/out, never intercepting touches.
    func refreshChip(_ active: Bool, topInset: CGFloat) -> some View {
        overlay(alignment: .top) {
            if active {
                RefreshChip()
                    .padding(.top, topInset)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}

#Preview {
    Color.appBase
        .refreshChip(true, topInset: 60)
        .ignoresSafeArea()
}
