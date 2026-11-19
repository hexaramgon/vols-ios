//
//  NowPlayingCommentsModel.swift
//  Volspire
//
//  Shared comments state so the list (which slides into the artwork box) and the
//  input bar (which the Comments button morphs into, at the bottom) can be two
//  separate views in different parts of the layout.
//

import Foundation
import Services
import SharedUtilities

@MainActor
@Observable
final class NowPlayingCommentsModel {
    var commentText: String = ""
    var comments: [ApiTrackComment] = []
    var isLoading = false
    /// The last comments fetch got no response (used as an offline indicator).
    var loadFailed = false
    var isSending = false
    /// Set when a post fails, so the composer can surface why instead of silently
    /// restoring the text. Cleared on the next send.
    var sendError: String?
    var currentUser: ApiUserSummary?
    /// Playback position (seconds) to pin the next comment to; nil = no timestamp.
    var commentTimestamp: Double?
    /// Optional end of a timestamp range (set by pressing the clock a 2nd time).
    var commentTimestampEnd: Double?
    /// When set, the next send is a reply to this comment (shown as a banner).
    var replyingTo: ApiTrackComment?
    /// Bumped on every Reply tap — tapping Reply on the comment already being
    /// replied to (keyboard dismissed since) changes nothing else, so the
    /// composer refocuses and the list re-scrolls off this instead.
    var replyRequest = 0

    func reply(to comment: ApiTrackComment) {
        replyingTo = comment
        replyRequest += 1
    }
    /// True while the composer input is focused (keyboard up). The comments panel
    /// reads this so a tap dismisses the keyboard instead of opening a profile.
    var composerFocused = false
    /// Screen Y of the composer card's visible top while it's lifted over the
    /// keyboard (`.greatestFiniteMagnitude` when it isn't) — the comments list
    /// insets its bottom by this so "just above the composer" is real.
    var composerTopY: CGFloat = .greatestFiniteMagnitude
    /// A comment to scroll to and briefly highlight in the panel — set when the
    /// live comment toast over the cover is tapped.
    var highlightedCommentId: String?

    func isOwn(_ comment: ApiTrackComment) -> Bool {
        // `currentUserId` is an uppercase uuidString; the DB returns lowercase —
        // compare case-insensitively. Use the auth id directly (the profile fetch
        // for `currentUser` can fail).
        guard let uid = supabaseService.currentUserId else { return false }
        return comment.user.userId.caseInsensitiveCompare(uid) == .orderedSame
    }

    /// The track / file the current `comments` belong to.
    private(set) var loadedKey: String?
    /// The item the panel is showing now — the latest one asked for. A reply
    /// (load, post, delete) that lands after a skip is for an older item and
    /// must not touch this one's list or composer.
    private var requestedKey: String?
    private let supabaseService = SupabaseService()

    var canSend: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// Loads comments for the current item — a workspace file (`fileId`) or a
    /// track (`trackId`). File comments take precedence when both are set.
    func loadComments(trackId: String?, fileId: String? = nil) async {
        let key = fileId ?? trackId
        guard let key else { return }
        requestedKey = key
        // Back on the item already listed (a skip there and back): its
        // comments are up — an in-flight load for the other one is dropped.
        guard key != loadedKey else { isLoading = false; return }
        isLoading = true
        do {
            let rows = if let fileId {
                try await supabaseService.getFileComments(fileId: fileId)
            } else {
                try await supabaseService.getTrackComments(trackId: key)
            }
            guard requestedKey == key else { return }
            comments = rows
            loadedKey = key
            loadFailed = false
            isLoading = false
        } catch {
            // A skip cancels this load (`.task(id:)`) — not a failure; the
            // newer load owns the list and the spinner.
            guard requestedKey == key, !error.isCancellation else { return }
            debugLog("[NowPlayingComments] load failed: \(error)")
            comments = []
            loadFailed = true
            isLoading = false
        }
    }

    private func isCurrent(_ key: String?) -> Bool { key != nil && key == requestedKey }

    func loadCurrentUser() async {
        guard currentUser == nil, let uid = supabaseService.currentUserId else { return }
        if let profile = try? await supabaseService.getUserProfile(userId: uid) {
            currentUser = ApiUserSummary(
                userId: uid,
                username: profile.username,
                profileImageUrl: profile.profileImageUrl
            )
        }
    }

    func send(trackId: String?, fileId: String? = nil) {
        // Cap to the server-side `comments` / `file_comments` CHECK length (defence in
        // depth; the DB constraint is authoritative since a raw RPC bypasses the client).
        let content = commentText.trimmingCharacters(in: .whitespacesAndNewlines).capped(at: InputLimits.comment)
        guard !content.isEmpty, !isSending, (trackId != nil || fileId != nil) else { return }
        let replyTo = replyingTo
        let parentId = replyTo?.commentId
        // Replies don't carry a timestamp (matches the web).
        let timestamp = parentId == nil ? commentTimestamp : nil
        let timestampEnd = parentId == nil ? commentTimestampEnd : nil
        commentText = ""
        commentTimestamp = nil
        commentTimestampEnd = nil
        replyingTo = nil
        sendError = nil

        // Optimistic insert so it appears instantly: top-level at the top,
        // replies under their parent.
        let tempId = "local-\(UUID().uuidString)"
        if let user = currentUser {
            let newComment = ApiTrackComment(
                commentId: tempId,
                content: content,
                createdAt: MessageTime.isoNow(),
                trackId: trackId,
                parentId: parentId,
                user: user,
                replies: nil,
                timestampSeconds: timestamp,
                timestampEndSeconds: timestampEnd
            )
            if let parentId, let idx = comments.firstIndex(where: { $0.commentId == parentId }) {
                comments[idx].replies = (comments[idx].replies ?? []) + [newComment]
            } else {
                comments.insert(newComment, at: 0)
            }
        }
        isSending = true
        let key = fileId ?? trackId

        Task {
            defer { isSending = false }
            do {
                if let fileId {
                    try await supabaseService.postFileComment(content: content, fileId: fileId, parentId: parentId, timestampSeconds: timestamp, timestampEndSeconds: timestampEnd)
                } else if let trackId {
                    try await supabaseService.postComment(content: content, trackId: trackId, parentId: parentId, timestampSeconds: timestamp, timestampEndSeconds: timestampEnd)
                    AnalyticsService.shared?.log(.commentPosted, trackId: trackId, metadata: ["kind": "track", "parent_id": parentId.map { .string($0) } ?? .null])
                }
                // Skipped meanwhile: that item reloads when it's next shown.
                guard isCurrent(key) else { return }
                loadedKey = nil
                await loadComments(trackId: trackId, fileId: fileId)
            } catch {
                debugLog("[NowPlayingComments] post failed: \(error)")
                // Skipped meanwhile: don't put that item's draft into this
                // one's composer.
                guard isCurrent(key) else {
                    ToastCenter.shared.show("Couldn't post your comment.", style: .error)
                    return
                }
                sendError = "Couldn't post your comment. Please try again."
                removeComment(tempId)
                commentText = content
                commentTimestamp = timestamp
                commentTimestampEnd = timestampEnd
                replyingTo = replyTo
            }
        }
    }

    /// Deletes a comment (own only) — optimistic, restoring on failure.
    func delete(commentId: String, trackId: String?, fileId: String? = nil) {
        guard trackId != nil || fileId != nil else { return }
        let snapshot = comments
        let key = fileId ?? trackId
        removeComment(commentId)
        Task {
            do {
                if let fileId {
                    try await supabaseService.deleteFileComment(commentId: commentId, fileId: fileId)
                } else if let trackId {
                    try await supabaseService.deleteComment(commentId: commentId, trackId: trackId)
                }
                ToastCenter.shared.show("Comment deleted")
            } catch {
                debugLog("[NowPlayingComments] delete failed: \(error)")
                if isCurrent(key) { comments = snapshot }
                ToastCenter.shared.show("Couldn't delete the comment — it's back.", style: .error)
            }
        }
    }

    /// Removes a comment whether it's top-level or a nested reply.
    private func removeComment(_ id: String) {
        comments.removeAll { $0.commentId == id }
        for idx in comments.indices {
            comments[idx].replies?.removeAll { $0.commentId == id }
        }
    }
}
