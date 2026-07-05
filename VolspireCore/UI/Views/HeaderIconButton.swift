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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LucideIcon(icon, size: ViewConst.headerIconSize)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
