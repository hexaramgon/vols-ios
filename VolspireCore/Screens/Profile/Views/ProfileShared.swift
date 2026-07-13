//
//  ProfileShared.swift
//  Volspire
//
//  Small reusable atoms shared across the profile sections: layout constants,
//  count formatting, the badge / empty-state, and the now-playing equaliser.
//

import DesignSystem
import SwiftUI

// MARK: - Layout

enum ProfileLayout {
    /// Immersive hero height (~half the screen, with a floor for small devices).
    /// Main-actor because it reads `UIScreen`; only view code calls it.
    @MainActor
    static var heroHeight: CGFloat { max(UIScreen.size.height * 0.54, 380) }

    /// Canonical banner crop aspect (width ÷ height) — the hero's banner band
    /// (screen width over `heroHeight × 0.82` incl. top inset) works out to
    /// ≈0.92 on every modern iPhone, so a FIXED value keeps the stored crop
    /// identical no matter which device it was made on; displays aspect-fill
    /// the ≤1% remainder. (The web crops its wider band from the middle.)
    static let bannerCropAspect: CGFloat = 0.92
    /// Two-column grid used by the Services + Packs tabs.
    static var grid: [GridItem] {
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }
}

extension Int {
    /// Compact count formatting for stats / streams / downloads (1.2K, 3.4M).
    var profileCompact: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.0fK", Double(self) / 1_000) }
        return "\(self)"
    }
}

// MARK: - Empty state

struct ProfileEmptyState: View {
    let icon: LucideIcon.Name
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .xxl).foregroundStyle(Color.vText3.opacity(0.7))
            Text(title).font(.appSubheadline).foregroundStyle(Color.vText2)
            if let subtitle {
                Text(subtitle).font(.appCaption).foregroundStyle(Color.vText3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

// MARK: - Now-playing equaliser (matches LibraryScreen)

struct ProfileEqualizerBars: View {
    @State private var animating = false
    private let heights: [CGFloat] = [7, 13, 9]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2.5, height: animating ? heights[i] : 3)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.13),
                        value: animating
                    )
            }
        }
        .frame(width: 14, height: 13, alignment: .center)
        .onAppear { animating = true }
    }
}
