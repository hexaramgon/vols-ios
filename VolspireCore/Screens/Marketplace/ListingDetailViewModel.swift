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

    private let service = SupabaseService()
    private let storage = StorageService()

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

        if let updated = try? await fresh {
            listing = updated
            isSaved = updated.viewerHasSaved ?? isSaved
            status = updated.status ?? status
            isAuthor = updated.isAuthor ?? isAuthor
            existingConvoId = updated.viewerConvoId
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

    func toggleStatus() async {
        guard !isTogglingStatus else { return }
        isTogglingStatus = true
        let next = isClosed ? "open" : "closed"
        let previous = status
        status = next
        do {
            try await service.updateListingStatus(listingId: listing.listingId, status: next)
        } catch {
            status = previous
            debugLog("[ListingDetailVM] toggleStatus failed: \(error)")
        }
        isTogglingStatus = false
    }

    /// Deletes the listing. Returns true on success (the screen then dismisses).
    func deleteListing() async -> Bool {
        do {
            try await service.deleteListing(listingId: listing.listingId)
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
        guard !isSaving else { return }
        isSaving = true
        let next = !isSaved
        isSaved = next
        do {
            if next { try await service.saveListing(listingId: listing.listingId) }
            else { try await service.unsaveListing(listingId: listing.listingId) }
        } catch {
            isSaved = !next
            debugLog("[ListingDetailVM] toggleSave failed: \(error)")
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
            return (convoId, nil)
        } catch {
            return (nil, respondError(error))
        }
    }

    private func respondError(_ error: Error) -> String {
        let msg = error.serverRawDetail
        if msg.contains("cannot_respond_to_own_listing") { return "You can't respond to your own listing." }
        if msg.contains("listing_closed") { return "This listing is closed." }
        if msg.contains("message_too_long") { return "Your message is too long." }
        if msg.contains("message_required") { return "Write a message first." }
        return "Couldn't send your message. Please try again."
    }

    // MARK: - Comments

    func postComment() async {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPostingComment else { return }
        isPostingComment = true
        do {
            let comment = try await service.postListingComment(listingId: listing.listingId, content: trimmed)
            comments.insert(comment, at: 0)
            commentText = ""
            AnalyticsService.shared?.log(.commentPosted, metadata: ["kind": "listing", "listing_id": .string(listing.listingId)])
        } catch {
            debugLog("[ListingDetailVM] postComment failed: \(error)")
            await loadComments()
        }
        isPostingComment = false
    }

    func deleteComment(_ comment: ApiListingComment) async {
        let snapshot = comments
        comments.removeAll { $0.commentId == comment.commentId }
        do {
            try await service.deleteListingComment(commentId: comment.commentId)
        } catch {
            comments = snapshot
            debugLog("[ListingDetailVM] deleteComment failed: \(error)")
        }
    }

    func isOwnComment(_ comment: ApiListingComment) -> Bool {
        guard let uid = currentUserId else { return false }
        return comment.user.userId.caseInsensitiveCompare(uid) == .orderedSame
    }

    // MARK: - Clip playback

    /// Playable URL for a clip attachment (bare storage path → full URL).
    func clipURL(_ attachment: ApiListingAttachment) -> URL? {
        guard let path = attachment.fileUrl,
              let urlString = storage.resolveTrackUrl(path) else { return nil }
        return URL(string: urlString)
    }
}
