//
//  AccentPillButton.swift
//  Volspire
//
//  The gradient accent pill ("+ New" / "Create") used by populated rail headers
//  (see the empty-rail CTA pattern), and the small gradient category chip used
//  on listing rows. One home for the accent-capsule chrome — don't re-roll.
//

import DesignSystem
import SwiftUI

struct AccentPillButton: View {
    let title: String
    var icon: LucideIcon.Name = .plus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                LucideIcon(icon, .sm)
                Text(title)
            }
            .font(.appFootnoteMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(LinearGradient.sendAccent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

/// The small gradient category/label chip (listing rows, hero chips).
struct AccentChip: View {
    let text: String
    var icon: LucideIcon.Name? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { LucideIcon(icon, .xs) }
            Text(text)
        }
        .font(.appCaption2Semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(LinearGradient.sendAccent, in: Capsule())
    }
}
