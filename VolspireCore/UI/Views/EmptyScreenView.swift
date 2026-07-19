//
//  EmptyScreenView.swift
//  Volspire
//

import DesignSystem
import SwiftUI

/// The app's standard empty-state placeholder — a Lucide hero icon, a title, and
/// an optional message. Use this instead of re-rolling per-screen empty-state
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
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appTitle3).foregroundStyle(.white)
            if let message {
                Text(message)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .multilineTextAlignment(.center)
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
