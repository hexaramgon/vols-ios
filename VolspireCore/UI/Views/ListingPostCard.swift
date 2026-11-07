//
//  ListingPostCard.swift
//  Volspire
//
//  THE listing card, wherever listings are listed (web `ListingCard` in
//  listing-post-cards.tsx): the Home Listings tab, the Collab tab's preview,
//  the board and a profile's Listings tab. A quiet byline (avatar · @author ·
//  category · age), the ask as the headline, a three-line body preview, then
//  the standard footer — counts on the left, round icon actions on the right.
//  The whole card opens the listing; the buttons do their own thing.
//
//  Save state comes from the shared ListingsStore (the viewer's saved-listings
//  list, with its optimistic overrides), so a save here shows on the detail
//  page and vice versa.
//

import DesignSystem
import Services
import SwiftUI

struct ListingPostCard: View {
    let listing: ApiListing
    /// Respond action (opens the respond composer). Nil = the card's Reply
    /// opens the listing detail, where Respond lives. Never shown on your own
    /// listing (the RPC rejects it anyway).
    var onRespond: (() -> Void)? = nil
    /// The reply icon opens the respond sheet right here (Home) instead of
    /// the listing page. A repeat response lands in the same DM.
    var respondInSheet = false
    /// Inside padding left/right — the Home feed runs it tighter.
    var horizontalInset: CGFloat = 20

    @Environment(Router.self) private var router
    @Environment(ListingsStore.self) private var listingsStore
    @Environment(Dependencies.self) private var dependencies
    @State private var showRespond = false
    @State private var isResponding = false

    private var isOwn: Bool {
        guard let me = dependencies.authManager.currentUserId else { return false }
        return listing.author.userId.lowercased() == me.lowercased()
    }

    private var saved: Bool {
        listingsStore.isSaved(listing.listingId, fallback: listing.viewerHasSaved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            byline

            Text(listing.title)
                .font(.appCalloutSemibold)
                .foregroundStyle(Color.vText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)

            if let desc = listing.description, !desc.isEmpty {
                Text(desc)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }

            footer.padding(.top, 16)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 16)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentShape(.rect(cornerRadius: Radius.card))
        .onTapGesture { router.navigateToCollabListing(listing) }
        // Feed rows carry no viewer flags — warm the saved list once so the
        // bookmarks are right (guarded: a no-op after the first load).
        .task { await listingsStore.loadSavedIfNeeded() }
        .sheet(isPresented: $showRespond) {
            RespondSheet(author: listing.author, listingTitle: listing.title, isSending: isResponding) { message in
                await respond(message)
            }
        }
    }

    /// Sends the response, then opens the DM it started. Returns an error
    /// string on failure (the sheet shows it), nil on success.
    private func respond(_ message: String) async -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Write a message first." }
        isResponding = true
        defer { isResponding = false }
        do {
            let convoId = try await dependencies.supabaseService.respondToListing(listingId: listing.listingId, message: trimmed)
            listingsStore.listingResponded(listing.listingId)
            Haptics.success()
            showRespond = false
            router.navigateToConversation(ActiveConversation(
                convoId: convoId,
                otherUserId: listing.author.userId,
                username: listing.author.username,
                avatarURL: listing.author.profileImageUrl
            ))
            return nil
        } catch {
            return ListingDetailViewModel.respondError(error)
        }
    }

    // MARK: - Byline

    private var byline: some View {
        HStack(spacing: 6) {
            Button { router.navigateToProfile(userId: listing.author.userId) } label: {
                HStack(spacing: 8) {
                    AvatarView(urlString: listing.author.profileImageUrl, name: listing.author.username, size: 24)
                    Text("@\(listing.author.username)")
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)
            Text("· \(listing.categoryLabel)")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
                .lineLimit(1)
                .fixedSize()

            Text("· \(MessageTime.ago(MessageTime.parse(listing.createdAt)))")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 20) {
            // Views are private to the author (the server only sends them
            // for your own listings).
            if isOwn, let views = listing.viewCount { ListingViewCount(count: views) }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                commentsAction
                // Bare icons (no fill). Saved = the filled bookmark in full ink.
                CardActionIcon(
                    icon: saved ? .bookmarkFill : .bookmark,
                    active: saved,
                    activeColor: .vSaved
                ) {
                    let next = !saved
                    Task { await listingsStore.setSaved(next, listing: listing) }
                }
                .accessibilityLabel(saved ? "Saved" : "Save")
                if !isOwn {
                    CardActionIcon(icon: .reply) {
                        if let onRespond { onRespond() }
                        else if respondInSheet { showRespond = true }
                        else { router.navigateToCollabListing(listing) }
                    }
                    .accessibilityLabel("Respond")
                }
                CardActionIcon(icon: .share2) { share() }
                    .accessibilityLabel("Share")
                    // Optically flush the last glyph with the card's edge.
                    .padding(.trailing, -8)
            }
        }
        .frame(height: 32)
    }

    /// The comments action: the same bare glyph as save / respond / share,
    /// with the count tucked beside it (none at zero). Opens the listing.
    private var commentsAction: some View {
        let count = listing.commentCount ?? 0
        return Button { router.navigateToCollabListing(listing) } label: {
            HStack(spacing: 3) {
                LucideIcon(.messageCircle, size: 22)
                if count > 0 {
                    Text(count.compactCount)
                        .font(.appSubheadlineMedium)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Color.inkText(0.78))
            .padding(.horizontal, 8)
            .frame(height: 38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count == 0 ? "Comments" : "\(count) comments")
    }

    private func share() {
        AnalyticsService.shared?.log(.shareClicked, metadata: ["kind": "listing", "method": "share_sheet"])
        UIApplication.presentActivitySheet(["\(listing.title) on Volspire https://volspire.com/listing/\(listing.listingId)"])
    }
}

/// A listing's footer action (cards + the full listing page): a bare 22pt
/// glyph (no circle) in a 38pt tap target.
/// `active` draws it in full ink; `popOn` plays the 1 → 1.12 → 1 pop each
/// time it flips on (Save → Saved).
struct CardActionIcon: View {
    let icon: LucideIcon.Name
    var active: Bool = false
    /// The glyph's colour while `active` (full ink; the saved bookmark's red).
    var activeColor: Color = .vText
    var popOn: Bool = false
    /// Glyph size; the 38pt target grows with it (the detail page's footer
    /// uses a larger glyph than the cards).
    var size: CGFloat = 22
    let action: () -> Void

    @State private var popScale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            // Between the old 20pt grey and the 24pt near-white try.
            Group {
                if icon == .bookmark || icon == .bookmarkFill {
                    // The shared save glyph (fill + pop + ripple on save).
                    SaveBookmarkIcon(saved: active, size: size)
                } else {
                    LucideIcon(icon, size: size)
                        .foregroundStyle(active ? activeColor : Color.inkText(0.78))
                }
            }
                .frame(width: size + 16, height: size + 16)
                .contentShape(.rect)
                .scaleEffect(popScale)
        }
        .buttonStyle(.plain)
        .onChange(of: popOn) { _, on in
            guard on else { return }
            withAnimation(.spring(duration: 0.16)) { popScale = 1.12 }
            withAnimation(.spring(duration: 0.16).delay(0.16)) { popScale = 1 }
        }
    }
}

/// Listing-card bones: three 160pt `vCardSolid` blocks (web `ListingCards`
/// loading state). Rows only — callers supply the scroll container.
struct ListingPostCardSkeleton: View {
    var count = 3

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0 ..< count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.vCardSolid)
                    .frame(height: 160)
            }
        }
        .shimmering()
    }
}

/// "👁 12 views" for the author of a listing — the board's view count is
/// private to them (`get_listings_feed` / `get_listing` send it only to the
/// author). One view per person per day.
struct ListingViewCount: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            LucideIcon(.eye, .sm)
            Text(count == 1 ? "1 view" : "\(count.compactCount) views")
                .font(.appFootnote)
                .monospacedDigit()
        }
        .foregroundStyle(Color.vText3)
        .accessibilityElement(children: .combine)
    }
}
