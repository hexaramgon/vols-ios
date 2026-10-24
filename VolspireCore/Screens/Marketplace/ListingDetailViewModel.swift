//
//  ListingDetailViewModel.swift
//  Volspire
//
//  Drives the collab-board listing detail: fetches the full listing (viewer
//  flags), save/unsave, respond (message the author), and comments. Clip
//  playback itself lives in the shared AudioAttachmentPlayer — this only
//  resolves the storage paths it plays.
//

import Foundation
import Observation
import Services
import SharedUtilities
import SwiftUI

@MainActor
@Observable
final class ListingDetailViewModel {
    private(set) var listing: ApiListing
    private(set) var comments: [ApiListingComment] = []
    private(set) var commentsLoaded = false

    var isSaved: Bool
    var status: String
    private(set) var isAuthor: Bool
    private(set) var existingConvoId: String?
    private(set) var responses: [ApiListingResponse] = []
    private(set) var responsesLoaded = false

    var isSaving = false
    var isResponding = false
    var isPostingComment = false
    var isTogglingStatus = false
    var commentText = ""
    /// The inline reply field's draft (under `replyingTo`'s row).
    var replyText = ""
    /// Set when `get_listing` says the listing is gone (deleted / private).
    private(set) var notFound = false
    /// User-facing reason the last comment post failed (shown in an ErrorBanner
    /// above the composer); cleared on the next attempt.
    var commentError: String?
    /// The top-level comment the composer is replying to (nil = a new thread).
    var replyingTo: ApiListingComment?

    private let service = SupabaseService()
    private let storage = StorageService()
    /// The shared listings store (assigned by the screen's `.task`) — shared
    /// mutations report to it so the board/saved lists patch in place.
    weak var listings: ListingsStore?

    init(listing: ApiListing) {
        self.listing = listing
        self.isSaved = listing.viewerHasSaved ?? false
        self.status = listing.status ?? "open"
        // Derive author-ownership up front from the signed-in user so the detail
        // doesn't flash the "Posted by" card before `load()` confirms it's yours
        // (the board feed sends `is_author = nil`).
        self.isAuthor = listing.isAuthor
            ?? (listing.author.userId.caseInsensitiveCompare(service.currentUserId ?? "") == .orderedSame)
        self.existingConvoId = listing.viewerConvoId
    }

    var currentUserId: String? { service.currentUserId }
    var isClosed: Bool { status == "closed" }

    func load() async {
        // Fetch the fresh listing, comments and (author-only) responses concurrently
        // instead of waterfalling getListing → comments → responses, so the detail
        // resolves in one pass — the body and both skeleton'd sections fill in
        // together rather than popping in one after another.
        async let fresh = service.getListing(listingId: listing.listingId)
        async let commentsDone: Void = loadComments()
        async let responsesDone: Void = loadResponsesIfAuthor()

        do {
            let updated = try await fresh
            listing = updated
            isSaved = updated.viewerHasSaved ?? isSaved
            status = updated.status ?? status
            isAuthor = updated.isAuthor ?? isAuthor
            existingConvoId = updated.viewerConvoId
            // Fresh detail truth → sync any board/saved copies' status+counts.
            listings?.applyFresh(updated)
        } catch {
            // Only a confirmed miss flips to "not found" — a network blip
            // keeps showing the copy we navigated in with.
            if error.serverRawDetail.contains("not_found") || error is DecodingError { notFound = true }
        }
        _ = await (commentsDone, responsesDone)
    }

    /// Author-only responses, loaded concurrently with comments. `isAuthor` is
    /// derived up front in `init` (a reliable userId match), so gating on it here —
    /// before the fresh listing lands — is safe.
    private func loadResponsesIfAuthor() async {
        if isAuthor { await loadResponses() }
    }

    // MARK: - Author management

    func loadResponses() async {
        responses = (try? await service.getListingResponses(listingId: listing.listingId)) ?? []
        responsesLoaded = true
    }

    /// Returns true when the server took the change (the screen confirms it).
    @discardableResult
    func toggleStatus() async -> Bool {
        guard !isTogglingStatus else { return false }
        isTogglingStatus = true
        let next = isClosed ? "open" : "closed"
        do {
            try await service.updateListingStatus(listingId: listing.listingId, status: next)
            // Applied only once it's real (the confirm sheet shows progress),
            // animated so the page eases into its new state.
            withAnimation(.smooth(duration: 0.35)) { status = next }
            listings?.setStatus(listingId: listing.listingId, status: next)
            isTogglingStatus = false
            return true
        } catch {
            debugLog("[ListingDetailVM] toggleStatus failed: \(error)")
            isTogglingStatus = false
            return false
        }
    }

    /// Deletes the listing. Returns true on success (the screen then dismisses).
    func deleteListing() async -> Bool {
        do {
            try await service.deleteListing(listingId: listing.listingId)
            listings?.listingDeleted(listing.listingId)
            return true
        } catch {
            debugLog("[ListingDetailVM] deleteListing failed: \(error)")
            return false
        }
    }

    func loadComments() async {
        comments = (try? await service.getListingComments(listingId: listing.listingId)) ?? []
        commentsLoaded = true
    }

    // MARK: - Save

    func toggleSave() async {
        guard !isSaving, let listings else { return }
        isSaving = true
        let next = !isSaved
        isSaved = next
        // The store owns the RPC + the Saved list membership (and rolls back
        // on failure); mirror its settled answer locally.
        if let settled = await listings.setSaved(next, listing: listing) {
            isSaved = settled
        } else {
            isSaved = !next
        }
        isSaving = false
    }

    // MARK: - Respond

    /// Sends `message` to the author. Returns the conversation id on success, or
    /// a user-facing error string.
    func respond(message: String) async -> (convoId: String?, error: String?) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, "Write a message first.") }
        isResponding = true
        defer { isResponding = false }
        do {
            let convoId = try await service.respondToListing(listingId: listing.listingId, message: trimmed)
            existingConvoId = convoId
            listings?.listingResponded(listing.listingId)
            return (convoId, nil)
        } catch {
            return (nil, Self.respondError(error))
        }
    }

    /// User-facing copy for a failed `respond_to_listing` (also used by the
    /// listing cards' in-place respond sheet).
    static func respondError(_ error: Error) -> String {
        let msg = error.serverRawDetail
        if msg.contains("cannot_respond_to_own_listing") { return "You can't respond to your own listing." }
        if msg.contains("listing_closed") { return "This listing is closed." }
        if msg.contains("message_too_long") { return "Your message is too long." }
        if msg.contains("message_required") { return "Write a message first." }
        return "Couldn't send your message. Please try again."
    }

    // MARK: - Comments

    /// Opens (or closes, when already open) the inline reply field under a
    /// top-level comment (one level of nesting).
    func toggleReply(to comment: ApiListingComment) {
        guard comment.parentId == nil else { return }
        if replyingTo?.commentId == comment.commentId {
            replyingTo = nil
        } else {
            replyingTo = comment
            replyText = ""
        }
        commentError = nil
    }

    /// Posts the top-level composer's text.
    func postComment() async {
        if await post(commentText, parentId: nil) { commentText = "" }
    }

    /// Posts the inline reply under `replyingTo`.
    func postReply() async {
        guard let parentId = replyingTo?.commentId else { return }
        if await post(replyText, parentId: parentId) {
            replyText = ""
            replyingTo = nil
        }
    }

    private func post(_ text: String, parentId: String?) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPostingComment else { return false }
        isPostingComment = true
        defer { isPostingComment = false }
        commentError = nil
        do {
            let comment = try await service.postListingComment(
                listingId: listing.listingId, content: trimmed, parentId: parentId
            )
            if let parentId, let idx = comments.firstIndex(where: { $0.commentId == parentId }) {
                // Nest the reply under its parent (server returns it oldest-last).
                comments[idx].replies = (comments[idx].replies ?? []) + [comment]
            } else {
                comments.insert(comment, at: 0)
            }
            listings?.commentDelta(listing.listingId, 1)
            bumpCommentCount(1)
            AnalyticsService.shared?.log(.commentPosted, metadata: ["kind": "listing", "listing_id": .string(listing.listingId)])
            return true
        } catch {
            debugLog("[ListingDetailVM] postComment failed: \(error)")
            commentError = commentErrorMessage(error)
            return false
        }
    }

    /// Keeps the footer's comment stat in step with local inserts/deletes.
    private func bumpCommentCount(_ delta: Int) {
        listing.commentCount = max(0, (listing.commentCount ?? 0) + delta)
    }

    /// The reasons `post_listing_comment` raises, in words (mirrors the web's
    /// useListingComments). The draft stays in the composer so it can be retried.
    private func commentErrorMessage(_ error: Error) -> String {
        let msg = error.serverRawDetail
        if msg.contains("not_authenticated") { return "Sign in again and retry." }
        if msg.contains("comment_required") { return "Write something first." }
        if msg.contains("comment_too_long") { return "Keep it under 1,000 characters." }
        if msg.contains("listing_not_found") { return "This listing is closed or no longer available." }
        return "Couldn't post your comment. Try again."
    }

    func deleteComment(_ comment: ApiListingComment) async {
        let snapshot = comments
        // A top-level delete cascades its replies server-side — the board's
        // count drops by the whole thread.
        let removedCount = comment.parentId == nil ? 1 + (comment.replies?.count ?? 0) : 1
        if let parentId = comment.parentId,
           let idx = comments.firstIndex(where: { $0.commentId == parentId }) {
            comments[idx].replies?.removeAll { $0.commentId == comment.commentId }
        } else {
            // Deleting a top-level comment cascades its replies server-side.
            comments.removeAll { $0.commentId == comment.commentId }
        }
        do {
            try await service.deleteListingComment(commentId: comment.commentId)
            listings?.commentDelta(listing.listingId, -removedCount)
            bumpCommentCount(-removedCount)
        } catch {
            comments = snapshot
            debugLog("[ListingDetailVM] deleteComment failed: \(error)")
        }
    }

    func isOwnComment(_ comment: ApiListingComment) -> Bool {
        guard let uid = currentUserId else { return false }
        return comment.user.userId.caseInsensitiveCompare(uid) == .orderedSame
    }

    /// Commenters delete their own; the listing author can delete any
    /// (`delete_listing_comment` allows both).
    func canDeleteComment(_ comment: ApiListingComment) -> Bool {
        isAuthor || isOwnComment(comment)
    }

    /// The web link shared from the footer's Share button.
    var shareURL: String { "https://volspire.com/listing/\(listing.listingId)" }

    // MARK: - Clip playback

    /// Playable URL for a clip attachment (bare storage path → full URL).
    func clipURL(_ attachment: ApiListingAttachment) -> URL? {
        guard let path = attachment.fileUrl,
              let urlString = storage.resolveTrackUrl(path) else { return nil }
        return URL(string: urlString)
    }
}
