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
                        .font(.appHeadline)
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
            Text(listing.author.username)
                .font(.appCalloutSemibold)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("· \(MessageTime.ago(MessageTime.parse(listing.createdAt)))")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
                .lineLimit(1)
            Spacer(minLength: 8)
            categoryChip
        }
    }

    private var categoryChip: some View {
        Text(listing.category.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.appCaption2Semibold)
            .foregroundStyle(Color.vText2)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.vSurface, in: Capsule())
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
        Group {
            if let url = listing.author.profileImageUrl.flatMap({ URL(string: $0) }) {
                KFImage(url).downsampled(to: 44).resizable().scaledToFill()
            } else {
                Text(String(listing.author.username.first ?? "?").uppercased())
                    .font(.appHeadline)
                    .foregroundStyle(Color.vText2)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color.vSurface)
        .clipShape(Circle())
    }
}
