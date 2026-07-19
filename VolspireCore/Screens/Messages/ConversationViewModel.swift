//
//  ConversationViewModel.swift
//  Volspire
//
//  Loads + sends messages (text + attachments) for a single conversation,
//  mirroring the web app's `useConvoMessages` hook (get_convo_messages /
//  send_message / send_message_with_attachment / mark_convo_read). Realtime
//  isn't wired on iOS yet, so new messages are picked up by a light poll.
//

import Foundation
import Services
import UIKit
import SharedUtilities

/// Strips metadata from image attachments before upload.
enum ImageSanitizer {
    /// Re-encodes a still image as baseline JPEG. UIImage bakes orientation into the
    /// pixels and the JPEG re-encode carries no EXIF/GPS/TIFF metadata, so this drops
    /// any embedded location. Returns nil if the bytes aren't a decodable image
    /// (caller keeps the original). Animated GIFs must be excluded by the caller —
    /// a single-frame re-encode would drop the animation.
    static func jpegStrippingMetadata(_ data: Data, quality: CGFloat = 0.9) -> Data? {
        UIImage(data: data)?.jpegData(compressionQuality: quality)
    }
}

/// A track shared in a collab-request message — resolved from the message's
/// structured `request_metadata.track_ids` (not parsed from text/URLs).
struct SharedTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String?
    let coverURL: URL?
    let audioURL: URL?
    let artistUserId: String?
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let isFromMe: Bool
    let createdAt: Date
    let type: String        // "message" | "system" | "collab_request" | …
    let isAttachment: Bool
    let attachmentURL: URL?
    let attachmentType: String?
    let attachmentName: String?
    var pending: Bool = false
    /// Tracks referenced by a collab request, resolved to render-ready cards.
    var sharedTracks: [SharedTrack] = []
    /// Collab-request lifecycle — drives the inline Accept/Decline UI.
    var requestId: String? = nil
    var requestStatus: String? = nil        // mutated optimistically on respond
    var requestFromUserId: String? = nil

    var isSystem: Bool { type == "system" }
    var isImageAttachment: Bool { isAttachment && (attachmentType?.hasPrefix("image") ?? false) }
    var isAudioAttachment: Bool { isAttachment && (attachmentType?.hasPrefix("audio") ?? false) }
    var isCollabRequest: Bool { type == "collab_request" }
    /// A collab request still awaiting a decision.
    var isPendingRequest: Bool {
        isCollabRequest && requestStatus != "accepted" && requestStatus != "rejected"
    }
}

extension ConversationViewModel {
    /// True when a collab request in this thread was accepted — the other
    /// participant is a collaborator (drives the "Remove Collaborator" option).
    var hasAcceptedCollabRequest: Bool {
        messages.contains { $0.isCollabRequest && $0.requestStatus == "accepted" }
    }
}

@Observable
@MainActor
final class ConversationViewModel {

    var messages: [ChatMessage] = []
    var loadingState: LoadState = .idle
    var draft = ""
    var isSending = false
    var attachmentError: String?

    let convoId: String
    private let currentUserId: String?
    private let service: SupabaseService
    private let storage: StorageService
    /// Resolved shared tracks, cached across polls (keyed by track id).
    private var sharedTrackCache: [String: SharedTrack] = [:]

    init(
        convoId: String,
        currentUserId: String?,
        service: SupabaseService = SupabaseService(),
        storage: StorageService = StorageService()
    ) {
        self.convoId = convoId
        self.currentUserId = currentUserId
        self.service = service
        self.storage = storage
    }

    /// `settleDelay` defers *applying* the result (not fetching it): the first
    /// load happens during the nav-push animation, and building the full thread
    /// mid-transition stutters — so the fetch overlaps the push, but the heavy
    /// first render waits until the transition has settled. Costs nothing on a
    /// slow network (the delay runs concurrently with the fetch).
    func load(settleDelay: Duration = .zero) async {
        if messages.isEmpty { loadingState = .loading }
        async let settled: Void = Self.sleep(settleDelay)
        do {
            let rows = try await service.getConvoMessages(convoId: convoId, limit: 50, offset: 0)
            let mapped = (await mapAll(rows)).sorted { $0.createdAt < $1.createdAt }
            await settled
            messages = mapped
            loadingState = .loaded
            try? await service.markConvoRead(convoId: convoId)
            PushNotificationManager.shared.clearDeliveredNotifications(convoId: convoId)
            await PushNotificationManager.shared.refreshBadge()
        } catch {
            debugLog("[ConversationVM] load: \(error)")
            await settled
            if messages.isEmpty { loadingState = .error(error.localizedDescription) }
        }
    }

    private static func sleep(_ duration: Duration) async {
        guard duration > .zero else { return }
        try? await Task.sleep(for: duration)
    }

    /// Matches the server-side `convo_messages.content` length cap (defence in depth;
    /// the server CHECK is authoritative since a raw RPC call bypasses the client).
    static let maxMessageLength = 4000

    func send() async {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxMessageLength))
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true

        let tempId = "local-\(UUID().uuidString)"
        let sentAt = Date()
        messages.append(ChatMessage(id: tempId, text: text, isFromMe: true, createdAt: sentAt,
                                    type: "message", isAttachment: false, attachmentURL: nil,
                                    attachmentType: nil, attachmentName: nil, pending: true))

        do {
            let newId = try await service.sendMessage(convoId: convoId, content: text)
            if let i = messages.firstIndex(where: { $0.id == tempId }) {
                messages[i] = ChatMessage(id: newId, text: text, isFromMe: true, createdAt: sentAt,
                                          type: "message", isAttachment: false, attachmentURL: nil,
                                          attachmentType: nil, attachmentName: nil, pending: false)
            }
        } catch {
            debugLog("[ConversationVM] send: \(error)")
            messages.removeAll { $0.id == tempId }
            draft = text   // restore the unsent text so it isn't lost
        }
        isSending = false
    }

    /// Uploads + sends an attachment (with an optional caption from the draft).
    /// Mirrors the server's `send_message_with_attachment` MIME allowlist so the
    /// client rejects unsupported files up front instead of uploading then failing.
    static let allowedAttachmentTypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/gif",
        "audio/mpeg", "audio/wav", "audio/x-wav", "audio/aac", "audio/mp4", "audio/flac", "audio/ogg",
        "video/mp4", "video/quicktime", "video/webm",
        "application/pdf", "text/plain", "application/zip",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ]

    func sendAttachment(data: Data, fileName: String, fileType: String, caption: String) async {
        guard let userId = currentUserId, !isSending else { return }

        // Strip EXIF/GPS from still images by re-encoding to JPEG off the main
        // thread. (Avatars/covers already do this; the DM path previously shipped
        // the original bytes, leaking any embedded location.) Animated GIFs are left
        // intact; a decode failure falls through to the original bytes. Normalising
        // to JPEG also brings iPhone HEIC photos into the server's allowlist.
        var uploadData = data
        var uploadName = fileName
        var uploadType = fileType
        if fileType.hasPrefix("image"), fileType != "image/gif",
           let cleaned = await Task.detached(priority: .userInitiated, operation: {
               ImageSanitizer.jpegStrippingMetadata(data)
           }).value {
            uploadData = cleaned
            uploadName = (fileName as NSString).deletingPathExtension + ".jpg"
            uploadType = "image/jpeg"
        }

        guard uploadData.count <= 25 * 1024 * 1024 else {
            attachmentError = "File is too large (max 25 MB)."
            return
        }
        guard Self.allowedAttachmentTypes.contains(uploadType) else {
            attachmentError = "That file type isn't supported."
            return
        }

        let text = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxMessageLength))
        isSending = true
        let tempId = "local-\(UUID().uuidString)"
        let sentAt = Date()
        messages.append(ChatMessage(id: tempId, text: text, isFromMe: true, createdAt: sentAt,
                                    type: "message", isAttachment: true, attachmentURL: nil,
                                    attachmentType: uploadType, attachmentName: uploadName, pending: true))

        do {
            let path = try await service.uploadMessageAttachment(
                convoId: convoId, userId: userId, fileName: uploadName, data: uploadData, fileType: uploadType
            )
            let newId = try await service.sendMessageWithAttachment(
                convoId: convoId, content: text, fileUrl: path, fileType: uploadType,
                fileName: uploadName, fileSize: uploadData.count
            )
            let signed = (await storage.signAttachmentUrls(paths: [path])).first ?? nil
            if let i = messages.firstIndex(where: { $0.id == tempId }) {
                messages[i] = ChatMessage(id: newId, text: text, isFromMe: true, createdAt: sentAt,
                                          type: "message", isAttachment: true,
                                          attachmentURL: signed.flatMap { URL(string: $0) },
                                          attachmentType: uploadType, attachmentName: uploadName, pending: false)
            }
        } catch {
            debugLog("[ConversationVM] sendAttachment: \(error)")
            messages.removeAll { $0.id == tempId }
            attachmentError = "Couldn't send the attachment."
        }
        isSending = false
    }

    /// Polls for new messages every few seconds while the thread is on screen.
    func startPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { break }
            await mergeLatest()
        }
    }

    private func mergeLatest() async {
        guard let rows = try? await service.getConvoMessages(convoId: convoId, limit: 50, offset: 0) else { return }
        let mapped = await mapAll(rows)
        let existing = Set(messages.map(\.id))
        let fresh = mapped.filter { !existing.contains($0.id) }

        // Sync request status on rows we already have — it flips when the other
        // party (or another device) responds while the thread is open, and the
        // header's Pending chip / ✕✓ buttons key off it.
        let byId = Dictionary(mapped.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in messages.indices {
            if let updated = byId[messages[i].id], updated.requestStatus != messages[i].requestStatus {
                messages[i].requestStatus = updated.requestStatus
            }
        }

        guard !fresh.isEmpty else { return }
        messages.append(contentsOf: fresh)
        messages.sort { $0.createdAt < $1.createdAt }
        if fresh.contains(where: { !$0.isFromMe }) {
            try? await service.markConvoRead(convoId: convoId)
            PushNotificationManager.shared.clearDeliveredNotifications(convoId: convoId)
            await PushNotificationManager.shared.refreshBadge()
        }
    }

    /// Signed attachment URLs cached per storage path, so the 4s poll doesn't re-sign
    /// every message's attachment on each tick (a full storage round-trip). The signed
    /// URL is valid ~1h; we cache well under that and re-sign lazily past the TTL.
    private var signedURLCache: [String: (url: String, at: Date)] = [:]
    private static let signedURLTTL: TimeInterval = 45 * 60  // < the 1h signed-URL expiry

    /// Maps rows to chat messages: signs any *new* attachment paths (cached per path)
    /// and batch-resolves any collab-request track references into cards.
    private func mapAll(_ rows: [ApiConvoMessage]) async -> [ChatMessage] {
        let paths: [String?] = rows.map { ($0.attachment ?? false) ? $0.attachmentUrl : nil }

        // Only sign paths without a fresh cached URL — the poll otherwise re-signs all
        // 50 rows' attachments every 4s even when nothing changed.
        let now = Date()
        let stale = Array(Set(paths.compactMap { $0 }).filter { path in
            guard let cached = signedURLCache[path] else { return true }
            return now.timeIntervalSince(cached.at) >= Self.signedURLTTL
        })
        if !stale.isEmpty {
            let fresh = await storage.signAttachmentUrls(paths: stale.map { Optional($0) })
            for (i, path) in stale.enumerated() where fresh[i] != nil {
                signedURLCache[path] = (fresh[i]!, now)
            }
        }

        let signed: [String?] = paths.map { path in path.flatMap { signedURLCache[$0]?.url } }
        let tracks = await resolveSharedTracks(rows)
        return rows.enumerated().map { idx, m in map(m, signedURL: signed[idx], tracks: tracks) }
    }

    /// Resolves every distinct referenced track id, fetching only the ones not
    /// already cached (so the 4s poll doesn't re-fetch unchanged tracks).
    private func resolveSharedTracks(_ rows: [ApiConvoMessage]) async -> [String: SharedTrack] {
        let ids = Set(rows.flatMap { $0.requestMetadata?.trackIds ?? [] })
        let missing = ids.filter { sharedTrackCache[$0] == nil }
        if !missing.isEmpty, let fetched = try? await service.getTracksByIds(Array(missing)) {
            for t in fetched {
                sharedTrackCache[t.trackId] = SharedTrack(
                    id: t.trackId,
                    title: t.title ?? "Track",
                    artist: t.artistUsername,
                    coverURL: storage.resolveTrackUrl(t.coverUrl).flatMap { URL(string: $0) },
                    audioURL: storage.resolveTrackUrl(t.audioUrl).flatMap { URL(string: $0) },
                    artistUserId: t.artistUserId
                )
            }
        }
        return sharedTrackCache
    }

    private func map(_ m: ApiConvoMessage, signedURL: String?, tracks: [String: SharedTrack]) -> ChatMessage {
        let type = m.messageType ?? "message"
        let isAttachment = m.attachment ?? false
        let shared = (m.requestMetadata?.trackIds ?? []).compactMap { tracks[$0] }
        return ChatMessage(
            id: m.messageId,
            text: m.content ?? "",
            // Case-insensitive: UUIDs are case-insensitive by spec, and the two
            // sides can differ in case (Postgres text is lowercase; some SDK paths
            // yield uppercase).
            isFromMe: type != "system" && m.userId != nil && m.userId?.lowercased() == currentUserId?.lowercased(),
            createdAt: MessageTime.parse(m.createdAt) ?? Date(),
            type: type,
            isAttachment: isAttachment,
            attachmentURL: signedURL.flatMap { URL(string: $0) },
            attachmentType: m.attachmentType,
            attachmentName: m.attachmentName,
            sharedTracks: shared,
            requestId: m.requestId,
            requestStatus: m.requestStatus,
            requestFromUserId: m.requestFromUserId
        )
    }

    /// Accepts or declines a collab request, updating the bubble in place.
    func respondToRequest(_ message: ChatMessage, accept: Bool) async {
        guard let requestId = message.requestId, message.isPendingRequest else { return }
        // Optimistic: flip the status now, revert on failure.
        let previous = message.requestStatus
        setRequestStatus(message.id, accept ? "accepted" : "rejected")
        do {
            if accept {
                try await service.acceptRequest(requestId: requestId)
            } else {
                try await service.rejectRequest(requestId: requestId)
            }
        } catch {
            debugLog("[ConversationVM] respondToRequest: \(error)")
            setRequestStatus(message.id, previous)
        }
    }

    private func setRequestStatus(_ messageId: String, _ status: String?) {
        guard let i = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[i].requestStatus = status
    }
}
