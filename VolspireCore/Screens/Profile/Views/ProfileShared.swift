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
    /// Canonical banner crop aspect (width ÷ height), SHARED WITH THE WEB:
    /// 16:9 — the middle ground between the iPhone hero's tall band and the
    /// desktop web hero's wide strip. Each display aspect-fills its own shape
    /// from the centre; the cropper's guides (`bannerGuides`) show both.
    static let bannerCropAspect: CGFloat = 16.0 / 9.0
    /// Exported banner width (px) — 2400×1350, so the iPhone hero (which fills
    /// by HEIGHT, ~1130px at 3x) never has to upscale it.
    static let bannerOutputSize: CGFloat = 2400
    /// What each platform's profile hero shows of a banner (width ÷ height):
    /// the iPhone hero band (≈0.92) and the desktop web hero (≈2.5:1).
    static let bannerGuides: [CropGuide] = [
        CropGuide(label: "iPhone", aspect: 0.92),
        CropGuide(label: "Desktop", aspect: 2.5),
    ]
    /// Two-column grid used by the Services + Packs tabs.
    static var grid: [GridItem] {
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }
}

extension Int {
    /// Compact count formatting for stats / streams / downloads (1.2K, 3.4M).
    var compactCount: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.0fK", Double(self) / 1_000) }
        return "\(self)"
    }

    /// "m:ss" duration label from a whole number of seconds.
    var durationLabel: String { String(format: "%d:%02d", self / 60, self % 60) }
}

extension Double {
    /// "m:ss" duration label from seconds; "0:00" for a non-finite/negative value.
    var durationLabel: String {
        guard isFinite, self >= 0 else { return "0:00" }
        return Int(rounded()).durationLabel
    }

    /// A price label — `$`/`€`/`£` for USD/EUR/GBP, else an unambiguous code
    /// suffix (e.g. "5 CAD"); trims a whole amount's decimals. `free: true`
    /// renders "Free" for a price of 0 or less.
    func priceLabel(currency: String? = nil, free: Bool = false) -> String {
        if free, self <= 0 { return "Free" }
        let amount = self == rounded() ? String(format: "%.0f", self) : String(format: "%.2f", self)
        switch (currency ?? "USD").uppercased() {
        case "USD": return "$\(amount)"
        case "EUR": return "€\(amount)"
        case "GBP": return "£\(amount)"
        default: return "\(amount) \((currency ?? "").uppercased())"
        }
    }
}

// MARK: - Empty state

/// A profile tab's empty state — between the old breathing ghost rows and a
/// bare glyph: a small fanned stack of cards (the tab's glyph on the front
/// one) over a short title. Still once landed — it lands with a
/// single soft fade + rise, never loops (under the hero, motion read as
/// loading).
struct ProfileEmptyState: View {
    let icon: LucideIcon.Name
    let title: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        VStack(spacing: 18) {
            stack
            Text(title)
                .font(.appSubheadlineSemibold)
                .foregroundStyle(Color.vText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .opacity(landed || reduceMotion ? 1 : 0)
        .offset(y: landed || reduceMotion ? 0 : 6)
        .onAppear {
            withAnimation(.timingCurve(0.25, 0, 0, 1, duration: 0.35)) { landed = true }
        }
        .accessibilityElement(children: .combine)
    }

    /// Two faint cards fanned behind a front card holding the glyph.
    private var stack: some View {
        ZStack {
            card.opacity(0.45).rotationEffect(.degrees(-10)).offset(x: -16, y: 4)
            card.opacity(0.7).rotationEffect(.degrees(8)).offset(x: 16, y: 2)
            card
                .overlay {
                    LucideIcon(icon, .xl).foregroundStyle(Color.vText2)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .frame(width: 104, height: 72)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.vCardSolid)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.vDivider, lineWidth: 1)
            }
            .frame(width: 60, height: 60)
    }
}

// MARK: - Now-playing equaliser (matches LibraryScreen)

