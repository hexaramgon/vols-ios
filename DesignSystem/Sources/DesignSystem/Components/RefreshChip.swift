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
            .tint(Color.vText)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
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

/// Runs a pull-to-refresh behind a `refreshChip`: sets `isRefreshing`, does
/// the work, and keeps the chip up at least ~0.6s — a fast refresh otherwise
/// flashed it for a frame and read as "nothing happened".
@MainActor
public func runRefresh(_ isRefreshing: Binding<Bool>, _ work: () async -> Void) async {
    isRefreshing.wrappedValue = true
    let start = ContinuousClock.now
    await work()
    let minimum = Duration.milliseconds(600)
    let elapsed = ContinuousClock.now - start
    if elapsed < minimum { try? await Task.sleep(for: minimum - elapsed) }
    isRefreshing.wrappedValue = false
}

#Preview {
    Color.appBase
        .refreshChip(true, topInset: 60)
        .ignoresSafeArea()
}
