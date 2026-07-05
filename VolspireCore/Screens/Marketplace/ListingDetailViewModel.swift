//
//  ListingDetailViewModel.swift
//  Volspire
//
//  Drives the collab-board listing detail: fetches the full listing (viewer
//  flags), save/unsave, respond (message the author), comments, and inline
//  playback of the attached audio clips.
//

import AVFoundation
import Foundation
import Observation
import Services

@MainActor
@Observable
final class ListingDetailViewModel {
    private(set) var listing: ApiListing
    private(set) var comments: [ApiListingComment] = []
    private(set) var commentsLoaded = false

    var isSaved: Bool
    var saveCount: Int
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

    /// `file_url` of the clip currently playing, or nil.
    private(set) var playingClip: String?

    private let service = SupabaseService()
    private let storage = StorageService()
    private var clipPlayer: AVPlayer?

    init(listing: ApiListing) {
        self.listing = listing
        self.isSaved = listing.viewerHasSaved ?? false
        self.saveCount = listing.saveCount ?? 0
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
        if let fresh = try? await service.getListing(listingId: listing.listingId) {
            listing = fresh
            isSaved = fresh.viewerHasSaved ?? isSaved
            saveCount = fresh.saveCount ?? saveCount
            status = fresh.status ?? status
            isAuthor = fresh.isAuthor ?? isAuthor
            existingConvoId = fresh.viewerConvoId
        }
        await loadComments()
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
            print("[ListingDetailVM] toggleStatus failed: \(error)")
        }
        isTogglingStatus = false
    }

    /// Deletes the listing. Returns true on success (the screen then dismisses).
    func deleteListing() async -> Bool {
        do {
            try await service.deleteListing(listingId: listing.listingId)
            return true
        } catch {
            print("[ListingDetailVM] deleteListing failed: \(error)")
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
        saveCount = max(0, saveCount + (next ? 1 : -1))
        do {
            if next { try await service.saveListing(listingId: listing.listingId) }
            else { try await service.unsaveListing(listingId: listing.listingId) }
        } catch {
            isSaved = !next
            saveCount = max(0, saveCount + (next ? -1 : 1))
            print("[ListingDetailVM] toggleSave failed: \(error)")
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
        let msg = (error as NSError).localizedDescription
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
            print("[ListingDetailVM] postComment failed: \(error)")
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
            print("[ListingDetailVM] deleteComment failed: \(error)")
        }
    }

    func isOwnComment(_ comment: ApiListingComment) -> Bool {
        guard let uid = currentUserId else { return false }
        return comment.user.userId.caseInsensitiveCompare(uid) == .orderedSame
    }

    // MARK: - Clip playback

    func toggleClip(_ attachment: ApiListingAttachment) {
        guard let path = attachment.fileUrl else { return }
        if playingClip == path {
            clipPlayer?.pause()
            playingClip = nil
            return
        }
        guard let urlString = storage.resolveTrackUrl(path), let url = URL(string: urlString) else { return }
        clipPlayer?.pause()
        let player = AVPlayer(url: url)
        clipPlayer = player
        playingClip = path
        player.play()
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in if self?.playingClip == path { self?.playingClip = nil } }
        }
    }

    func stopClip() {
        clipPlayer?.pause()
        clipPlayer = nil
        playingClip = nil
    }
}
