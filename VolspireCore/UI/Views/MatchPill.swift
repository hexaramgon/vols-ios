//
//  MatchPill.swift
//  Volspire
//
//  The small accent pill a result wears while a filter is on, naming what it
//  matched ("Vocalist", "Producer", "Drum Kit") — so a filtered list says why
//  each item is in it. Not shown when nothing is filtered.
//

import DesignSystem
import SwiftUI

struct MatchPill: View {
    let label: String
    var icon: LucideIcon.Name? = nil
    /// Sits on artwork: a dark glass fill with white ink so it reads on any
    /// cover. Otherwise a soft accent tint with accent ink.
    var onImage = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { LucideIcon(icon, .xs) }
            Text(label).font(.appCaptionMedium).lineLimit(1)
        }
        .foregroundStyle(onImage ? Color.white : Color.vAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(onImage ? Color.black.opacity(0.55) : Color.vAccent.opacity(0.14), in: Capsule())
        .fixedSize()
    }
}
