//
//  MessagesScreenViewModel.swift
//  Volspire
//
//  Loads the signed-in user's conversation list (`get_user_conversations`),
//  mirroring the web app's `useConversations` hook + the messages page's
//  classification (Requests / Orders / Inquiries / Listings / Conversations /
//  Archived).
//

import Foundation
import Services
import SharedUtilities

struct ConversationItem: Identifiable, Hashable {
    let id: String          // convo_id
    let otherUserId: String?
    let username: String
    let title: String?
    let avatarURL: URL?
    let preview: String
    let lastMessageAt: Date?
    let unreadCount: Int
    let type: String
    let lastMessageType: String?
    let requestStatus: String?
    let archived: Bool
    /// The latest message is mine — in a pending request thread only the
    /// requester can speak, so this doubles as "I sent the request".
    let lastMessageFromMe: Bool

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

@Observable
@MainActor
final class MessagesScreenViewModel {

    /// All conversations (including archived) — buckets are derived below.
    var conversations: [ConversationItem] = []
    var loadingState: LoadState = .idle
    var searchText = ""
    /// Set by the screen before `load()` — drives request-direction wording.
    var currentUserId: String?

    private let service: SupabaseService

    init(service: SupabaseService = SupabaseService()) {
        self.service = service
    }

    // MARK: Search + buckets

    var filtered: [ConversationItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.username.lowercased().contains(query) || ($0.title?.lowercased().contains(query) ?? false)
        }
    }

    /// Pending collab requests — pinned at the top (web's "New message requests").
    var pendingRequests: [ConversationItem] { filtered.filter { $0.isPendingRequest && !$0.archived } }
    /// Purchase threads.
    var orders: [ConversationItem] { filtered.filter { $0.isOrder && !$0.archived } }
    /// Pre-purchase service chats.
    var inquiries: [ConversationItem] { filtered.filter { $0.isInquiry && !$0.archived } }
    /// Collab-board listing-response threads.
    var listings: [ConversationItem] { filtered.filter { $0.isListing && !$0.archived } }
    /// Everything else — DMs.
    var directConvos: [ConversationItem] {
        filtered.filter { !$0.isPendingRequest && !$0.isOrder && !$0.isInquiry && !$0.isListing && !$0.isArchivedRow }
    }
    /// Declined requests + archived threads (collapsed section).
    var archivedConvos: [ConversationItem] { filtered.filter { $0.isArchivedRow } }

    func load() async {
        if conversations.isEmpty { loadingState = .loading }
        do {
            let rows = try await service.getUserConversations(limit: 40, offset: 0)
            let me = currentUserId
            conversations = rows
                .map { Self.map($0, me: me) }
                .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
            loadingState = .loaded
        } catch {
            debugLog("[MessagesVM] load: \(error)")
            if conversations.isEmpty { loadingState = .error(error.localizedDescription) }
        }
    }

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
            case let t? where t.hasPrefix("audio"): return "Voice message"
            case let t? where t.hasPrefix("video"): return "Video"
            default: return "Attachment"
            }
        default: return "No messages yet"
        }
    }
}
