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
    /// A collab request its sender withdrew — still the latest message (once
    /// either of you writes again it's a normal conversation).
    var isWithdrawnRequest: Bool { isCollabRequest && requestStatus == "withdrawn" && !isOrder }
    /// A collab request still awaiting accept/decline. Surfaces under Requests
    /// whether the request is the latest message *or* got buried under later
    /// replies — an unanswered request shouldn't get lost in the main list just
    /// because the two of you kept chatting past it.
    var isPendingRequest: Bool {
        guard !isOrder, !isInquiry, !isListing else { return false }
        // Latest message is the request itself, still unresolved…
        if isCollabRequest && !["accepted", "rejected", "withdrawn"].contains(requestStatus ?? "pending") { return true }
        // …or the request is still pending, just no longer the last message.
        return requestStatus == "pending"
    }
    /// Declined / withdrawn requests + manually archived threads collapse into
    /// Archived — a dead request never sits in the main list.
    var isArchivedRow: Bool { isDeclinedRequest || isWithdrawnRequest || archived }
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
    /// The server has conversations past the loaded ones (the last page came
    /// back full) — list footers fetch the next page as they scroll into view.
    private(set) var hasMoreConversations = false
    private var isLoadingMore = false
    /// The last next-page fetch failed — the footer offers a retry instead of
    /// spinning.
    private(set) var pageLoadFailed = false
    /// Conversations per page (the RPC caps a page at 100).
    static let pageSize = 40
    /// Unread counts from `get_unread_counts` — the only fetch path for them.
    private(set) var unreadMessages = 0
    private(set) var unreadNotifications = 0
    /// The realtime listener (foreground only) and its open subscription.
    private var liveTask: Task<Void, Never>?
    private var liveSubscription: LiveEventsSubscription?

    /// The Explore tab's header hosts BOTH the Messages and bell buttons, so
    /// its tab-bar dot lights for either kind of unread (each header button
    /// shows only its own kind).
    var inboxHasUnread: Bool { unreadMessages > 0 || unreadNotifications > 0 }

    // MARK: Dependencies

    private let service: SupabaseService

    private var conversationsTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(service: SupabaseService) {
        self.service = service

        // A push landed while the app is open → the counts (and, for a
        // message, the conversation rows) are stale. Without this the banner
        // showed but no dot appeared until a tab switch or relaunch.
        observers.append(NotificationCenter.default.addObserver(
            forName: .pushReceived, object: nil, queue: .main
        ) { [weak self] note in
            let isMessage = note.userInfo?["convo_id"] != nil
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.syncAfterServerChange(includeConversations: isMessage) }
            }
        })
    }

    /// Foregrounding — anything may have arrived while backgrounded (pushes
    /// delivered to the lock screen never reach the app).
    func appBecameActive() async {
        await syncAfterServerChange(includeConversations: true)
    }

    /// Forced unread counts (a coalesced count from before the change would
    /// strand the dot) + the conversation list if it's already been loaded —
    /// so the row behind the Messages dot actually shows its unread state.
    private func syncAfterServerChange(includeConversations: Bool) async {
        async let unread: Void = refreshUnread(force: true)
        if includeConversations, loadState != .idle, conversationsTask == nil {
            await refreshConversations()
        }
        await unread
    }

    func resetForSignOut() {
        conversationsTask?.cancel()
        conversationsTask = nil
        conversations = []
        loadState = .idle
        hasMoreConversations = false
        unreadMessages = 0
        unreadNotifications = 0
        stopLiveUpdates()
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

    /// A user was blocked — their threads leave the inbox now.
    func removeConversations(with userId: String) {
        let id = key(userId)
        conversations.removeAll { $0.otherUserId.map(key) == id }
    }

    /// Opening Messages: first load, or — if loaded earlier this session —
    /// revalidate in place (rows stay on screen) so the list is never older
    /// than the dot that led here.
    func loadOrRevalidateConversations() async {
        if conversationsTask != nil || loadState == .idle {
            await loadConversationsIfNeeded()
        } else {
            await refreshConversations()
        }
    }

    /// Always refetches (the RPC is uncached) — pull-to-refresh + foreground.
    func refreshConversations() async {
        await fetchConversations()
    }

    /// The DM thread with `userId` (e.g. the collab-request thread a
    /// notification points at). Refetches once on a miss — the thread may be
    /// newer than the loaded list.
    func dmConversation(with userId: String) async -> ConversationItem? {
        await loadConversationsIfNeeded()
        let find = { [self] in
            conversations.first { $0.type == "dm" && $0.otherUserId.map(key) == key(userId) }
        }
        if let hit = find() { return hit }
        await refreshConversations()
        // An older thread lives past the loaded pages — page until it shows up.
        while find() == nil, hasMoreConversations {
            let before = conversations.count
            await loadMoreConversations()
            if conversations.count == before { break }   // failed / nothing new
        }
        return find()
    }

    /// Appends the next page. Offset paging over a newest-first list: activity
    /// since the last fetch shifts the window, so a page can re-deliver rows
    /// already shown — deduped by id.
    func loadMoreConversations() async {
        guard hasMoreConversations, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        pageLoadFailed = false
        do {
            let rows = try await service.getUserConversations(limit: Self.pageSize, offset: conversations.count)
            hasMoreConversations = rows.count == Self.pageSize
            let me = service.currentUserId
            let existing = Set(conversations.map(\.id))
            conversations = (conversations + rows.map { Self.map($0, me: me) }.filter { !existing.contains($0.id) })
                .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
        } catch {
            debugLog("[InboxStore] conversations page: \(error)")
            pageLoadFailed = true
        }
    }

    private func fetchConversations() async {
        do {
            let rows = try await service.getUserConversations(limit: Self.pageSize, offset: 0)
            let me = service.currentUserId
            let page = rows.map { Self.map($0, me: me) }
            // A refresh replaces the first page but keeps older pages already
            // loaded (rows past the page's oldest that it didn't re-deliver).
            let fresh = Set(page.map(\.id))
            let floor = page.last?.lastMessageAt ?? .distantPast
            let olderKept = rows.count == Self.pageSize
                ? conversations.filter { !fresh.contains($0.id) && ($0.lastMessageAt ?? .distantPast) < floor }
                : []
            if olderKept.isEmpty { hasMoreConversations = rows.count == Self.pageSize }
            conversations = (page + olderKept)
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

    // MARK: - Live in-app alerts

    /// While the app is open: listens on the user's private Supabase
    /// Realtime topic (`user:<uid>`, see LiveEvents.swift). A DB trigger
    /// broadcasts an ids-only event per new DM / activity row; we refetch via
    /// the normal RPCs, update the dots/list and show the in-app banner. No
    /// polling, and no dependence on APNs (an install without push permission
    /// still gets in-app alerts). A push that also arrives is deduped by
    /// `PushBannerCenter`. Design + rollback: docs/realtime-in-app-notifications.md.
    func startLiveUpdates() {
        guard liveTask == nil else { return }
        liveTask = Task { [weak self] in await self?.runLiveEvents() }
    }

    /// Backgrounding / sign-out: leave the channel (the socket closes with it).
    func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        if let subscription = liveSubscription {
            liveSubscription = nil
            Task { await subscription.close() }
        }
    }

    /// Joins the topic (retrying with backoff if the join fails) and handles
    /// events until cancelled. The SDK re-joins by itself after a dropped
    /// socket; anything missed meanwhile is caught by `appBecameActive`.
    private func runLiveEvents() async {
        var backoff: Double = 2
        while !Task.isCancelled {
            do {
                guard let subscription = try await service.openLiveEvents() else { return }
                guard !Task.isCancelled else { await subscription.close(); return }
                liveSubscription = subscription
                backoff = 2
                for await event in subscription.events {
                    await handle(event)
                }
            } catch {
                debugLog("[InboxStore] live events join failed: \(error)")
            }
            if let subscription = liveSubscription {
                liveSubscription = nil
                await subscription.close()
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 60)
        }
    }

    private func handle(_ event: LiveEvent) async {
        switch event {
        case .message(let convoId, _):
            async let unread: Void = refreshUnread(force: true)
            await refreshConversations()
            await unread
            announceMessage(convoId: convoId)
        case .activity:
            await refreshUnread(force: true)
            await announceNewActivity()
        }
    }

    /// Banners the conversation that just got a message — unless it's the
    /// one on screen, or it's already read / mine (e.g. sent from my other
    /// device).
    private func announceMessage(convoId: String) {
        let visible = PushNotificationManager.shared.visibleConversationId.map(key)
        guard key(convoId) != visible,
              let row = conversations.first(where: { key($0.id) == key(convoId) }),
              row.hasUnread, !row.lastMessageFromMe, !row.archived else { return }
        var info = ["type": "message", "convo_id": row.id, "title": row.username, "body": row.preview]
        info["sender_id"] = row.otherUserId
        PushBannerCenter.shared.show(info)
    }

    /// Banners the newest unread activity row, and lets an open
    /// Notifications page reload (same signal as an in-app push).
    private func announceNewActivity() async {
        guard let items = try? await service.getUserNotifications(force: true),
              let item = items.first(where: { !($0.isRead ?? false) }) else { return }
        var info = [
            "type": "activity",
            "title": item.actor?.username ?? "Notifications",
            "body": Self.activityText(item),
        ]
        info["object_type"] = item.objectType
        info["object_id"] = item.objectId
        PushBannerCenter.shared.show(info)
        NotificationCenter.default.post(name: .pushReceived, object: nil, userInfo: info)
    }

    /// Short banner copy — matches the push wording ("liked your track").
    private static func activityText(_ item: ApiNotification) -> String {
        let noun = switch item.objectType {
        case "listing", "pack", "service", "folder": item.objectType ?? "track"
        default: "track"
        }
        let action = item.action ?? ""
        switch action {
        case "liked", "saved", "shared": return "\(action) your \(noun)"
        case "commented": return "commented on your \(noun)"
        case "followed": return "started following you"
        default:
            let text = action.replacingOccurrences(of: "_", with: " ")
            if let title = item.objectTitle, !title.isEmpty { return "\(text) · \(title)" }
            return text.isEmpty ? "New activity" : text
        }
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
