//
//  ConversationViewModel.swift
//  Volspire
//
//  Loads + sends messages (text + attachments) for a single conversation,
//  mirroring the web app's `useConvoMessages` hook (get_convo_messages /
//  send_message / send_message_with_attachment / mark_convo_read). Realtime
//  isn't wired on iOS yet, so new messages are picked up by a light poll.
//

import DesignSystem
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
    /// Signed (expiring) link — re-resolved from `attachmentPath` while the
    /// thread is open (see `refreshAttachmentLinks`).
    var attachmentURL: URL?
    let attachmentType: String?
    let attachmentName: String?
    var pending: Bool = false
    /// Tracks referenced by a collab request, resolved to render-ready cards.
    var sharedTracks: [SharedTrack] = []
    /// Collab-request lifecycle — drives the inline Accept/Decline UI.
    var requestId: String? = nil
    var requestStatus: String? = nil        // mutated optimistically on respond
    var requestFromUserId: String? = nil
    /// The attachment's storage path — the stable key its link is signed from.
    var attachmentPath: String? = nil

    var isSystem: Bool { type == "system" }
    var isImageAttachment: Bool { isAttachment && (attachmentType?.hasPrefix("image") ?? false) }
    var isAudioAttachment: Bool { isAttachment && (attachmentType?.hasPrefix("audio") ?? false) }
    var isCollabRequest: Bool { type == "collab_request" }
    /// A collab request still awaiting a decision.
    var isPendingRequest: Bool {
        isCollabRequest && requestStatus != "accepted" && requestStatus != "rejected"
    }
}

/// Why the composer is closed while a collab request is open or declined.
/// A request is an ask, not an open channel — for either side: the requester
/// gets the one message the request carried, and the recipient answers it
/// (Accept / Decline) before the thread opens. Accepting is the only way in.
enum CollabRequestGate: Equatable {
    /// My request, waiting on the recipient.
    case awaitingReply
    /// My request, and they said no.
    case declined
    /// Their request, waiting on me.
    case needsResponse
    /// Their request, and I said no.
    case youDeclined

    var message: String {
        switch self {
        case .awaitingReply: "Waiting for a reply to your collab request. You can message once they accept."
        case .declined: "Your collab request was declined, so you can't send messages here."
        case .needsResponse: "Accept the collab request to start messaging, or decline it."
        case .youDeclined: "You declined this collab request, so messaging is closed."
        }
    }
}

extension ConversationViewModel {
    /// True when a collab request in this thread was accepted — the other
    /// participant is a collaborator (drives the "Remove Collaborator" option).
    var hasAcceptedCollabRequest: Bool {
        messages.contains { $0.isCollabRequest && $0.requestStatus == "accepted" }
    }

    /// Mirrors the server's `collab_request_gate` so the composer reflects what
    /// `send_message` would do rather than failing after the fact. The RPC stays
    /// authoritative — this only decides what the UI offers.
    ///
    /// Nil status reads as OPEN, matching the server: it means no `requests` row
    /// backs the message, which is the one case the gate lets through.
    var collabRequestGate: CollabRequestGate? {
        // Accepted anywhere in the thread = collaborators, gate lifted.
        guard !hasAcceptedCollabRequest else { return nil }
        // The latest request decides, whichever side sent it.
        guard let latest = messages.last(where: \.isCollabRequest) else { return nil }
        switch (latest.requestStatus, latest.isFromMe) {
        case ("pending", true): return .awaitingReply
        case ("rejected", true): return .declined
        case ("pending", false): return .needsResponse
        case ("rejected", false): return .youDeclined
        default: return nil
        }
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
    /// The server has messages older than the oldest one loaded (the last page
    /// came back full) — the thread offers "Load earlier messages".
    private(set) var hasOlder = false
    private(set) var isLoadingOlder = false
    /// The collab listing this conversation was opened from (Collab Board
    /// respond flow) — drives the "about this listing" banner. Nil for DMs.
    var linkedListing: ApiListing?

    let convoId: String
    /// The shared inbox store — the thread reports list-affecting events
    /// (latest message, read state, request status) so the conversation list
    /// updates in memory with no refetch on close.
    weak var inbox: InboxStore?
    /// The shared social store — collab accept/decline updates the overlay a
    /// mounted profile renders from.
    weak var social: SocialStore?
    /// The other participant (for the collab-status overlay writes).
    var otherUserId: String?
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
            let rows = try await service.getConvoMessages(convoId: convoId, limit: Self.pageSize, offset: 0)
            let mapped = (await mapAll(rows)).sorted { $0.createdAt < $1.createdAt }
            await settled
            // A reload (e.g. after a collab-gate rejection) replaces the latest
            // page but keeps any earlier pages the user already loaded.
            let fresh = Set(mapped.map(\.id))
            let oldest = mapped.first?.createdAt ?? .distantFuture
            let olderKept = messages.filter {
                !fresh.contains($0.id) && !$0.id.hasPrefix("local-") && $0.createdAt < oldest
            }
            if olderKept.isEmpty { hasOlder = rows.count == Self.pageSize }
            messages = olderKept + mapped
            loadingState = .loaded
            // The two follow-up chains are independent of each other — running
            // them concurrently collapses the old 4-deep serial tail
            // (mark-read → true-up → listing-id → listing) to one parallel
            // round of RTTs. mark-read stays AFTER a successful fetch so a
            // failed load can't clear the unread dot.
            async let readChain: Void = runMarkReadChain()
            async let listingChain: Void = resolveLinkedListing()
            _ = await (readChain, listingChain)
        } catch {
            debugLog("[ConversationVM] load: \(error)")
            await settled
            loadingState.fail(error, ifEmpty: messages.isEmpty)
        }
    }

    /// mark-read + dot/badge true-up (their internal order is a real dependency).
    private func runMarkReadChain() async {
        try? await service.markConvoRead(convoId: convoId)
        PushNotificationManager.shared.clearDeliveredNotifications(convoId: convoId)
        // markConvoRead has completed — the store zeroes the row and
        // trues up dots + app badge from the single unread pipeline.
        inbox?.threadMarkedRead(convoId: convoId)
    }

    /// Best-effort: resolve the listing this thread was opened from
    /// (one cheap id lookup; full fetch only for listing conversations).
    private func resolveLinkedListing() async {
        if linkedListing == nil,
           let listingId = try? await service.getConvoListingId(convoId: convoId),
           let listing = try? await service.getListing(listingId: listingId) {
            linkedListing = listing
        }
    }

    /// Messages per page — the first load, each "load earlier" step, and the poll.
    static let pageSize = 50

    /// Prepends the next page of older messages. The RPC pages newest-first by
    /// offset, so messages that arrived since the first load shift the window
    /// and can re-deliver a few already shown — deduped by id (never a gap).
    func loadOlder() async {
        guard hasOlder, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        let loaded = messages.filter { !$0.id.hasPrefix("local-") }.count
        do {
            let rows = try await service.getConvoMessages(convoId: convoId, limit: Self.pageSize, offset: loaded)
            hasOlder = rows.count == Self.pageSize
            let existing = Set(messages.map(\.id))
            let older = await mapAll(rows).filter { !existing.contains($0.id) }
            messages = (older + messages).sorted { $0.createdAt < $1.createdAt }
        } catch {
            debugLog("[ConversationVM] loadOlder: \(error)")
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
        guard !text.isEmpty, !isSending, collabRequestGate == nil else { return }
        draft = ""
        isSending = true

        let tempId = "local-\(UUID().uuidString)"
        let sentAt = Date()
        messages.append(ChatMessage(id: tempId, text: text, isFromMe: true, createdAt: sentAt,
                                    type: "message", isAttachment: false, attachmentURL: nil,
                                    attachmentType: nil, attachmentName: nil, pending: true))

        do {
            let newId = try await service.sendMessage(convoId: convoId, content: text)
            // The 4s poll can merge the server copy before this returns —
            // renaming the temp row too would duplicate the message (and its
            // SwiftUI id), so just drop the temp row then.
            if messages.contains(where: { $0.id == newId }) {
                messages.removeAll { $0.id == tempId }
            } else if let i = messages.firstIndex(where: { $0.id == tempId }) {
                messages[i] = ChatMessage(id: newId, text: text, isFromMe: true, createdAt: sentAt,
                                          type: "message", isAttachment: false, attachmentURL: nil,
                                          attachmentType: nil, attachmentName: nil, pending: false)
            }
            inbox?.threadLatestChanged(convoId: convoId, preview: text, at: sentAt, fromMe: true)
            inbox?.setDraft("", for: convoId)
        } catch {
            debugLog("[ConversationVM] send: \(error)")
            messages.removeAll { $0.id == tempId }
            draft = text   // restore the unsent text so it isn't lost
            inbox?.setDraft(text, for: convoId)   // …even if the screen closes
            await handleCollabGateRejection(error)
        }
        isSending = false
    }

    /// The server is authoritative on the collab gate, so it can refuse a send
    /// the UI thought was fine — the recipient may have declined mid-compose.
    /// Re-loading pulls the new request status, which swaps the composer for the
    /// explanation instead of leaving a silent failure.
    private func handleCollabGateRejection(_ error: Error) async {
        let detail = error.serverRawDetail
        guard detail.contains("collab_request_")
        else { return }
        await load()
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
        // An attachment is a message: same gate, checked before the upload so a
        // blocked send never puts bytes in storage.
        guard let userId = currentUserId, !isSending, collabRequestGate == nil else { return }

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

        let maxBytes = StorageBucket.messageAttachments.maxUploadBytes
        guard uploadData.count <= maxBytes else {
            attachmentError = FileTooLargeError(maxBytes: maxBytes).localizedDescription
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
            // Same poll race as `send()`: the server copy may already be merged.
            if messages.contains(where: { $0.id == newId }) {
                messages.removeAll { $0.id == tempId }
            } else if let i = messages.firstIndex(where: { $0.id == tempId }) {
                messages[i] = ChatMessage(id: newId, text: text, isFromMe: true, createdAt: sentAt,
                                          type: "message", isAttachment: true,
                                          attachmentURL: signed.flatMap { URL(string: $0) },
                                          attachmentType: uploadType, attachmentName: uploadName, pending: false,
                                          attachmentPath: path)
            }
            let label = text.isEmpty ? Self.attachmentLabel(uploadType) : text
            inbox?.threadLatestChanged(convoId: convoId, preview: label, at: sentAt, fromMe: true)
        } catch {
            debugLog("[ConversationVM] sendAttachment: \(error)")
            messages.removeAll { $0.id == tempId }
            attachmentError = "Couldn't send the attachment."
            await handleCollabGateRejection(error)
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
        guard let rows = try? await service.getConvoMessages(convoId: convoId, limit: Self.pageSize, offset: 0) else { return }
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

        await refreshAttachmentLinks()

        guard !fresh.isEmpty else { return }
        messages.append(contentsOf: fresh)
        messages.sort { $0.createdAt < $1.createdAt }
        // Keep the list row's preview/order live while the thread is open.
        if let last = messages.last {
            let label = last.text.isEmpty ? Self.attachmentLabel(last.attachmentType ?? "") : last.text
            inbox?.threadLatestChanged(
                convoId: convoId, preview: label, at: last.createdAt,
                fromMe: last.isFromMe, messageType: last.type
            )
        }
        if fresh.contains(where: { !$0.isFromMe }) {
            try? await service.markConvoRead(convoId: convoId)
            PushNotificationManager.shared.clearDeliveredNotifications(convoId: convoId)
            inbox?.threadMarkedRead(convoId: convoId)
        }
    }

    /// Preview label for an attachment-only message (mirrors the list mapping).
    private static func attachmentLabel(_ type: String) -> String {
        switch type.lowercased() {
        case let t where t.hasPrefix("image"): "Image"
        case let t where t.hasPrefix("audio"): "Audio"
        case let t where t.hasPrefix("video"): "Video"
        default: "Attachment"
        }
    }

    /// Maps rows to chat messages: signs attachment paths (through the shared
    /// signed-URL memo — a local lookup unless a link is new or nearing expiry)
    /// and batch-resolves any collab-request track references into cards.
    private func mapAll(_ rows: [ApiConvoMessage]) async -> [ChatMessage] {
        let paths: [String?] = rows.map { ($0.attachment ?? false) ? $0.attachmentUrl : nil }
        let signed = await storage.signAttachmentUrls(paths: paths)
        let tracks = await resolveSharedTracks(rows)
        return rows.enumerated().map { idx, m in map(m, signedURL: signed[idx], tracks: tracks) }
    }

    /// Signed attachment links expire after an hour, so an open thread re-resolves
    /// EVERY loaded attachment each poll (earlier pages too, not just the latest
    /// page the poll fetched). Through the shared memo that's a local lookup until
    /// a link nears expiry, then one batched re-sign — no dead links on screen.
    private func refreshAttachmentLinks() async {
        let paths = Array(Set(messages.compactMap(\.attachmentPath)))
        guard !paths.isEmpty else { return }
        let signed = await storage.signAttachmentUrls(paths: paths.map { Optional($0) })
        var byPath: [String: URL] = [:]
        for (path, link) in zip(paths, signed) {
            if let link, let url = URL(string: link) { byPath[path] = url }
        }
        for i in messages.indices {
            guard let path = messages[i].attachmentPath, let url = byPath[path],
                  messages[i].attachmentURL != url else { continue }
            messages[i].attachmentURL = url
        }
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
                    audioURL: storage.trackMediaURL(t.audioUrl),
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
            requestFromUserId: m.requestFromUserId,
            attachmentPath: isAttachment ? m.attachmentUrl : nil
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
            // The Requests bucket and any mounted profile's collab badge
            // re-derive from the shared stores. This thread IS the pair's DM,
            // so an accept also hands the profile its "Message" deep-link.
            if accept { Haptics.success() }
            inbox?.requestStatusChanged(convoId: convoId, status: accept ? "accepted" : "rejected")
            if let otherUserId {
                social?.recordCollabAnswer(accepted: accept, from: otherUserId)
                social?.setCollabStatus(
                    accept ? "accepted" : "none",
                    userId: otherUserId,
                    convoId: accept ? convoId : nil
                )
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
