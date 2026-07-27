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

    /// Buckets over the search-filtered rows — predicates live on the shared
    /// `bucket(_:)` helper so pushed folders classify identically.
    var pendingRequests: [ConversationItem] { filtered.bucket(.requests) }
    var orders: [ConversationItem] { filtered.bucket(.orders) }
    var inquiries: [ConversationItem] { filtered.bucket(.inquiries) }
    var listings: [ConversationItem] { filtered.bucket(.listings) }
    var directConvos: [ConversationItem] { filtered.bucket(.direct) }
    /// Declined requests + archived threads (collapsed section).
    var archivedConvos: [ConversationItem] { filtered.bucket(.archived) }
}
