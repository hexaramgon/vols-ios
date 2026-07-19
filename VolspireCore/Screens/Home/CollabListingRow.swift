//
//  CollabListingRow.swift
//  Volspire
//
//  A collab listing rendered as a Twitter-style feed row — author + relative
//  time, a category tag, the ask (title + description + hashtags), and an
//  engagement footer. Tapping opens the full ListingDetailScreen via the Router.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct CollabListingRow: View {
    let listing: ApiListing
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.navigateToCollabListing(listing)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 7) {
                    headerLine
                    Text(listing.title)
                        // Same style as the home track titles, so the feed reads as one.
                        .font(.appFont.trackTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let desc = listing.description, !desc.isEmpty {
                        Text(desc)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText2)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    if let tags = listing.tags, !tags.isEmpty {
                        tagRow(tags)
                    }
                    engagement
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
    }

    /// `username · 3h` on the left, the category as a chip on the right.
    private var headerLine: some View {
        HStack(spacing: 6) {
            // The home track cards' artist treatment: "@name" in grey caption.
            Text("@\(listing.author.username)")
                .font(.appFont.trackSubtitle)
                .foregroundStyle(Color.vText3)
                .lineLimit(1)
            Text("· \(MessageTime.ago(MessageTime.parse(listing.createdAt)))")
                .font(.appFont.trackSubtitle)
                .foregroundStyle(Color.vText3)
                .lineLimit(1)
            Spacer(minLength: 8)
            categoryChip
        }
    }

    private var categoryChip: some View {
        Text(listing.category.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.appCaption2Semibold)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            // Brand accent — matches the listing detail's category chip.
            .background(LinearGradient.sendAccent, in: Capsule())
    }

    private func tagRow(_ tags: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.vText3)
                    .lineLimit(1)
            }
        }
    }

    private var engagement: some View {
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
        }
        .foregroundStyle(Color.vText3)
    }

    private var avatar: some View {
        AvatarView(urlString: listing.author.profileImageUrl, name: listing.author.username, size: 38)
            // Optically align the circle's top with the "@name" cap height —
            // the taller category chip centers the username a few points below
            // the row's geometric top, so without this the avatar rides high.
            .padding(.top, 4)
    }
}
