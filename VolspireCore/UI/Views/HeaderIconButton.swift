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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LucideIcon(icon, size: ViewConst.headerIconSize)
                .foregroundStyle(.white)
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
