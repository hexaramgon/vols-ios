//
//  MessagesScreenViewModel.swift
//  Volspire
//
//  Screen-local search + bucket derivation over the shared InboxStore's
//  conversation list (the list itself, its loading, and unread counts live in
//  the store). Buckets mirror the web messages page's classification
//  (Requests / Orders / Inquiries / Listings / Conversations / Archived).
//

import Foundation
import Observation

@Observable
@MainActor
final class MessagesScreenViewModel {
    var searchText = ""
    /// The shared inbox store — assigned by the screen's `.task`.
    weak var inbox: InboxStore?

    private var all: [ConversationItem] { inbox?.conversations ?? [] }

    // MARK: Search + buckets

    var filtered: [ConversationItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter {
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
}
