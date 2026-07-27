//
//  InboxStore.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SharedUtilities

/// Single source of truth for the inbox: the conversation list and the app's
/// unread counts (DMs + notifications). This is THE `get_unread_counts`
/// pipeline — the tab dot, the bell dot, and the app-icon badge all derive
/// from the counts held here, refreshed in one place.
///
/// The message thread itself stays in `ConversationViewModel` (its polling
/// lifecycle is tied to the screen); the thread reports back via small event
/// hooks (message sent, thread read, request status changed) so the list and
/// dots update in memory with no refetch.
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

    init(service: SupabaseService) {
        self.service = service
    }

    func resetForSignOut() {
        conversations = []
        loadState = .idle
        unreadMessages = 0
        unreadNotifications = 0
    }
}
