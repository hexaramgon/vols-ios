//
//  BackButton.swift
//  Volspire
//
//  The shared pushed-screen back chevron. Replaces the `Image(systemName:
//  "chevron.left")` + font/shadow block copy-pasted across ~13 screens (and moves
//  them off SF Symbols to Lucide, per the icon convention). Defaults to dismissing;
//  pass a closure for custom back behaviour (e.g. onboarding step-back).
//

import DesignSystem
import SwiftUI

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    /// A subtle shadow keeps the chevron legible over hero art; turn it off for plain
    /// dark-background headers (search / analytics / edit-profile).
    var shadow: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button { (action ?? { dismiss() })() } label: {
            LucideIcon(.chevronLeft, size: ViewConst.backIconSize)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(shadow ? 0.5 : 0), radius: 2, y: 1)
                // Grow the hit area to ~44pt without moving any pixels (an
                // explicit frame would shift the chevron's leading alignment
                // at every call site).
                .contentShape(Rectangle().inset(by: -11))
        }
        .buttonStyle(.plain)
    }
}
