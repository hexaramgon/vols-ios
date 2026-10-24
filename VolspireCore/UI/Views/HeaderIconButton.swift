//
//  HeaderIconButton.swift
//  Volspire
//
//  The shared header action icon — bare (no background) 24pt glyph in a 42×42
//  tap target. Used by the Home, Library and Marketplace headers so they match.
//

import DesignSystem
import SwiftUI

struct HeaderIconButton: View {
    let icon: LucideIcon.Name
    /// Unread indicator — a small dot on the icon's top-trailing corner.
    var showDot: Bool = false
    /// Soft drop shadow for buttons floating over hero art (profile / detail
    /// pages) — keeps the glyph legible on bright covers.
    var shadow: Bool = false
    /// Glyph size — header rows use the default; hero-overlay buttons pass
    /// `ViewConst.heroOverlayIconSize`.
    var size: CGFloat = ViewConst.headerIconSize
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            LucideIcon(icon, size: size)
                .foregroundStyle(Color.vText)
                // The legibility shadow only makes sense for a light glyph over
                // art — pin hero overlays dark with `.alwaysDark()`.
                .shadow(color: .black.opacity(shadow && colorScheme == .dark ? 0.5 : 0), radius: 2, y: 1)
                .overlay(alignment: .topTrailing) {
                    if showDot {
                        Circle()
                            .fill(Color.vUnread)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
                .frame(width: 42, height: 42)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
