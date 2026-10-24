//
//  InboxStore.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SharedUtilities

/// One row of the conversation list. Mutable fields are the ones the thread's
/// event hooks patch in place (preview, ordering, read state, request status).
struct ConversationItem: Identifiable, Hashable {
    let id: String          // convo_id
    let otherUserId: String?
    let username: String
    let title: String?
    let avatarURL: URL?
    var preview: String
    var lastMessageAt: Date?
    var unreadCount: Int
    let type: String
    var lastMessageType: String?
    var requestStatus: String?
    let archived: Bool
    /// The latest message is mine — in a pending request thread only the
    /// requester can speak, so this doubles as "I sent the request".
    var lastMessageFromMe: Bool

    var hasUnread: Bool { unreadCount > 0 }

    // MARK: Classification (mirrors the web messages page buckets)

    var isOrder: Bool { type == "service_order" || type == "order" }
    var isInquiry: Bool { type == "service_inquiry" }
    var isListing: Bool { type == "listing_response" }
    private var isCollabRequest: Bool { lastMessageType == "collab_request" }
    /// A collab request the other side declined.
    var isDeclinedRequest: Bool { isCollabRequest && requestStatus == "rejected" && !isOrder }
    /// A collab request still awaiting accept/decline. Surfaces under Requests
    /// whether the request is the latest message *or* got buried under later
    /// replies — an unanswered request shouldn't get lost in the main list just
    /// because the two of you kept chatting past it.
    var isPendingRequest: Bool {
        guard !isOrder, !isInquiry, !isListing else { return false }
        // Latest message is the request itself, still unresolved…
        if isCollabRequest && requestStatus != "accepted" && requestStatus != "rejected" { return true }
        // …or the request is still pending, just no longer the last message.
        return requestStatus == "pending"
    }
    /// Declined requests + manually archived threads collapse into Archived.
    var isArchivedRow: Bool { isDeclinedRequest || archived }
}

/// The inbox's folder buckets. Routes carry the KEY (not a row snapshot), so
/// a pushed folder derives live rows from the store and never goes stale.
enum MessageBucket: String, Hashable {
    case requests, orders, inquiries, listings, direct, archived
}

extension [ConversationItem] {
    /// THE bucket predicates — shared by the inbox list (over its search-
    /// filtered rows) and pushed category folders (over the store's rows).
    func bucket(_ bucket: MessageBucket) -> [ConversationItem] {
        switch bucket {
        case .requests: filter { $0.isPendingRequest && !$0.archived }
        case .orders: filter { $0.isOrder && !$0.archived }
        case .inquiries: filter { $0.isInquiry && !$0.archived }
        case .listings: filter { $0.isListing && !$0.archived }
        case .direct: filter { !$0.isPendingRequest && !$0.isOrder && !$0.isInquiry && !$0.isListing && !$0.isArchivedRow }
        case .archived: filter { $0.isArchivedRow }
        }
    }
}

/// Single source of truth for the inbox: the conversation list and the app's
/// unread counts (DMs + notifications). This is THE `get_unread_counts`
/// pipeline — the tab dot, the bell dot, and the app-icon badge all derive
/// from the counts held here, refreshed in one place.
///
/// The message thread itself stays in `ConversationViewModel` (its polling
/// lifecycle is tied to the screen); the thread reports back via small event
/// hooks so the list and dots update in memory — closing a thread no longer
/// refetches the whole list.
@MainActor @Observable
final class InboxStore {
    // MARK: Server state

    /// The conversation list, newest first.
    private(set) var conversations: [ConversationItem] = []
    private(set) var loadState: LoadState = .idle
    /// Unread counts from `get_unread_counts` — the only fetch path for them.
    private(set) var unreadMessages = 0
    private(set) var unreadNotifications = 0

    /// The Inbox tab hosts BOTH the DM list and the notifications bell, so its
    /// tab-bar dot lights for either kind of unread.
    var inboxHasUnread: Bool { unreadMessages > 0 || unreadNotifications > 0 }

    // MARK: Dependencies

    private let service: SupabaseService

    private var conversationsTask: Task<Void, Never>?

    init(service: SupabaseService) {
        self.service = service
    }

    func resetForSignOut() {
        conversationsTask?.cancel()
        conversationsTask = nil
        conversations = []
        loadState = .idle
        unreadMessages = 0
        unreadNotifications = 0
        draftsByConvo = [:]
    }

    // MARK: - Conversation list

    func loadConversationsIfNeeded() async {
        if let conversationsTask { return await conversationsTask.value }
        guard case .idle = loadState else { return }
        loadState = .loading
        let task = Task { await fetchConversations() }
        conversationsTask = task
        await task.value
        conversationsTask = nil
    }

    /// Always refetches (the RPC is uncached) — pull-to-refresh + foreground.
    func refreshConversations() async {
        await fetchConversations()
    }

    private func fetchConversations() async {
        do {
            let rows = try await service.getUserConversations(limit: 40, offset: 0)
            let me = service.currentUserId
            conversations = rows
                .map { Self.map($0, me: me) }
                .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
            loadState = .loaded
        } catch {
            debugLog("[InboxStore] conversations load: \(error)")
            loadState.fail(error, ifEmpty: conversations.isEmpty)
        }
    }

    // MARK: - Unread counts (THE pipeline)

    /// Refreshes both dots AND the app-icon badge from one RPC — the single
    /// `get_unread_counts` path (previously fetched independently by the tab
    /// bar, the badge refresher, and per-screen counters).
    func refreshUnread(force: Bool = false) async {
        guard let counts = try? await service.getUnreadCounts(force: force) else { return }
        unreadMessages = counts.messages
        unreadNotifications = counts.notifications
        PushNotificationManager.shared.setBadge(counts.notifications + counts.messages)
    }

    /// Optimistic zero when the notifications screen opens (the server marks
    /// them read at the same moment); the badge drops to just the DM count.
    func clearNotificationsDot() {
        unreadNotifications = 0
        PushNotificationManager.shared.setBadge(unreadMessages)
    }

    // MARK: - Thread event hooks (called by ConversationViewModel)

    /// The thread's latest message changed (sent OR received while open) —
    /// patch the row's preview/order in place. No list refetch.
    func threadLatestChanged(convoId: String, preview: String, at date: Date, fromMe: Bool, messageType: String = "message") {
        guard let i = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        conversations[i].preview = preview
        conversations[i].lastMessageAt = date
        conversations[i].lastMessageFromMe = fromMe
        conversations[i].lastMessageType = messageType
        conversations.sort { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
    }

    /// The thread finished `markConvoRead` — zero its row and true-up the
    /// dots/badge from the server (safe ordering: the RPC has completed, so
    /// the refreshed counts can't resurrect the dot).
    func threadMarkedRead(convoId: String) {
        if let i = conversations.firstIndex(where: { $0.id == convoId }) {
            conversations[i].unreadCount = 0
        }
        // force: the mark-read just changed the truth — a coalesced count from
        // seconds ago would strand the dot.
        Task { await refreshUnread(force: true) }
    }

    /// Opening a thread reads it — zero the row immediately so the list behind
    /// the push never shows a stale dot.
    func conversationOpened(_ convoId: String) {
        guard let i = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        conversations[i].unreadCount = 0
    }

    /// A collab request was accepted/declined in the thread — the Requests /
    /// Archived buckets re-derive from the patched row.
    func requestStatusChanged(convoId: String, status: String) {
        guard let i = conversations.firstIndex(where: { $0.id == convoId }) else { return }
        conversations[i].requestStatus = status
    }

    // MARK: - Drafts

    /// Unsent composer text per conversation — survives closing the thread
    /// (session-scoped; cleared on send and at sign-out).
    private var draftsByConvo: [String: String] = [:]

    func draft(for convoId: String) -> String {
        draftsByConvo[key(convoId)] ?? ""
    }

    func setDraft(_ text: String, for convoId: String) {
        let k = key(convoId)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        draftsByConvo[k] = trimmed.isEmpty ? nil : text
    }

    private func key(_ raw: String) -> String { raw.lowercased() }

    // MARK: - Row mapping (from `get_user_conversations`)

    private static func map(_ c: ApiConversation, me: String?) -> ConversationItem {
        // Case-insensitive: Postgres UUIDs are lowercase, some SDK paths uppercase.
        let fromMe = me != nil && c.lastMessageUserId?.lowercased() == me?.lowercased()
        return ConversationItem(
            id: c.convoId,
            otherUserId: c.otherUserId,
            username: c.otherUsername ?? "Unknown",
            title: c.title,
            avatarURL: c.otherProfileImageUrl.flatMap { URL(string: $0) },
            preview: preview(for: c, fromMe: fromMe),
            lastMessageAt: MessageTime.parse(c.lastMessageAt),
            unreadCount: c.unreadCount ?? 0,
            type: c.type ?? "direct",
            lastMessageType: c.lastMessageType,
            requestStatus: c.requestStatus,
            archived: c.archivedAt != nil,
            lastMessageFromMe: fromMe
        )
    }

    /// Last-message preview text, with fallbacks that match the web's ConvoRow.
    private static func preview(for c: ApiConversation, fromMe: Bool) -> String {
        if let content = c.lastMessageContent, !content.isEmpty {
            // Strip a leading track-embed marker so previews read cleanly.
            if let range = content.range(of: "🎵") {
                let text = content[content.startIndex..<range.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
                return "Shared a track"
            }
            return content
        }
        switch c.lastMessageType {
        case "collab_request": return fromMe ? "Collab request sent" : "Collab request"
        case "message":
            switch c.lastMessageAttachmentType?.lowercased() {
            case let t? where t.hasPrefix("image"): return "Image"
            case let t? where t.hasPrefix("audio"): return "Audio"
            case let t? where t.hasPrefix("video"): return "Video"
            default: return "Attachment"
            }
        default: return "No messages yet"
        }
    }
}
