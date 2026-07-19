//
//  ListingRowBits.swift
//  Volspire
//
//  Shared leaf pieces of a collab-listing row — the "#tag" strip and the
//  responders/comments/saves stat row. Three renderers (the Collab feed row,
//  the profile Market tab, and the All-tab collab card) had re-rolled these,
//  drifting on the counts' `.fixedSize()` clipping fix.
//

import DesignSystem
import Services
import SwiftUI

/// Up to three "#tag" chips in the muted caption voice.
struct ListingTagRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.vText3)
                    .lineLimit(1)
            }
        }
    }
}

/// The engagement footer: responders / comments / saves.
struct ListingStatsRow: View {
    let listing: ApiListing

    var body: some View {
        HStack(spacing: 20) {
            stat(.users, listing.responseCount)        // responders
            stat(.messageCircle, listing.commentCount) // comments
            stat(.bookmark, listing.saveCount)         // saves
        }
    }

    private func stat(_ icon: LucideIcon.Name, _ count: Int?) -> some View {
        HStack(spacing: 5) {
            LucideIcon(icon, .sm)
            Text("\(count ?? 0)")
                .font(.appCaptionMedium)
                .monospacedDigit()
                // Never compress the counts — sharing a line with a spacer and
                // trailing chips squeezed them into clipped glyph slivers.
                .fixedSize()
        }
        .foregroundStyle(Color.vText3)
    }
}
