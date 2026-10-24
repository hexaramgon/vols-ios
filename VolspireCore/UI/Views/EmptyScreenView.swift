//
//  EmptyScreenView.swift
//  Volspire
//

import DesignSystem
import SwiftUI

/// The app's standard empty-state placeholder — a Lucide glyph in a 64pt
/// `vSurface` puck (r16), a title, and an optional message (max 280pt wide).
/// Callers add a CTA 24pt below. Use this instead of re-rolling per-screen empty-state
/// VStacks so they stay visually consistent.
struct EmptyStateView: View {
    let icon: LucideIcon.Name
    let title: String
    var message: String? = nil
    /// Expands to fill and centers vertically — replaces the per-screen
    /// wrapper frames some callers added around this view.
    var centered: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .xxl)
                .foregroundStyle(Color.vText3)
                .frame(width: 64, height: 64)
                .background(Color.vSurface, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                .padding(.bottom, 6)
            Text(title).font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
            if let message {
                Text(message)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: centered ? .infinity : nil)
        .padding(.horizontal, 40)
    }
}

#Preview {
    EmptyStateView(
        icon: .inbox,
        title: "Nothing here yet",
        message: "Content will show up here once it's available."
    )
}
