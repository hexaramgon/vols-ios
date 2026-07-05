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

    var hasUnread: Bool { unreadCount > 0 }

    // MARK: Classification (mirrors the web messages page buckets)

    var isOrder: Bool { type == "service_order" || type == "order" }
    var isInquiry: Bool { type == "service_inquiry" }
    var isListing: Bool { type == "listing_response" }
    private var isCollabRequest: Bool { lastMessageType == "collab_request" }
    /// A collab request the other side declined.
    var isDeclinedRequest: Bool { isCollabRequest && requestStatus == "rejected" && !isOrder }
    /// A collab request still awaiting accept/decline.
    var isPendingRequest: Bool {
        isCollabRequest && requestStatus != "accepted" && requestStatus != "rejected" && !isOrder
    }
    /// Declined requests + manually archived threads collapse into Archived.
    var isArchivedRow: Bool { isDeclinedRequest || archived }
}

@Observable
@MainActor
final class MessagesScreenViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, error(String) }

    /// All conversations (including archived) — buckets are derived below.
    var conversations: [ConversationItem] = []
    var loadingState: LoadState = .idle
    var searchText = ""

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
            conversations = rows
                .map(Self.map)
                .sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
            loadingState = .loaded
        } catch {
            print("[MessagesVM] load: \(error)")
            if conversations.isEmpty { loadingState = .error(error.localizedDescription) }
        }
    }

    private static func map(_ c: ApiConversation) -> ConversationItem {
        ConversationItem(
            id: c.convoId,
            otherUserId: c.otherUserId,
            username: c.otherUsername ?? "Unknown",
            title: c.title,
            avatarURL: c.otherProfileImageUrl.flatMap { URL(string: $0) },
            preview: preview(for: c),
            lastMessageAt: MessageTime.parse(c.lastMessageAt),
            unreadCount: c.unreadCount ?? 0,
            type: c.type ?? "direct",
            lastMessageType: c.lastMessageType,
            requestStatus: c.requestStatus,
            archived: c.archivedAt != nil
        )
    }

    /// Last-message preview text, with fallbacks that match the web's ConvoRow.
    private static func preview(for c: ApiConversation) -> String {
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
        case "collab_request": return "Collab request"
        case "message": return "Attachment"
        default: return "No messages yet"
        }
    }
}
