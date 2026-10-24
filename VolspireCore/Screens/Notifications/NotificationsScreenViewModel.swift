//
//  NotificationsScreenViewModel.swift
//  Volspire
//
//  Loads the signed-in user's notifications (`get_user_notifications`) and marks
//  them read on view, mirroring the web app's `useNotifications` hook.
//

import Foundation
import Observation
import Services
import SharedUtilities

/// A recency bucket ("New" / "Today" / … / "Older") for the grouped feed.
struct NotificationGroup: Identifiable {
    let id: String
    let title: String
    let items: [ApiNotification]
}

/// The filter-chip vocabulary (web `NOTIF_CATEGORIES`).
enum NotificationCategory: String, CaseIterable, Identifiable {
    case follows, likes, comments, collabs, workspace, sales, uploads

    var id: String { rawValue }

    var label: String {
        switch self {
        case .follows: "Follows"
        case .likes: "Likes"
        case .comments: "Comments"
        case .collabs: "Collabs"
        case .workspace: "Workspace"
        case .sales: "Sales"
        case .uploads: "Uploads"
        }
    }

    /// Chips shown — "Sales" only exists with the marketplace.
    static var visible: [NotificationCategory] {
        allCases.filter { FeatureFlags.marketplace || $0 != .sales }
    }

    /// The web's action → category map.
    static func of(_ action: String?) -> NotificationCategory? {
        switch action {
        case "followed": .follows
        case "liked", "saved", "shared": .likes
        case "commented", "commented on file": .comments
        case "requested collaboration", "accepted collaboration", "credited", "listing_response": .collabs
        case "shared folder", "added to folder", "uploaded file": .workspace
        case "purchased": .sales
        case "uploaded": .uploads
        default: nil
        }
    }
}

@Observable @MainActor
final class NotificationsScreenViewModel {
    var notifications: [ApiNotification] = []
    var loadingState: LoadState = .idle
    /// Active filter chip; nil = All.
    var filter: NotificationCategory?

    /// Ids that were unread when the screen opened. The UI highlights against
    /// this snapshot so the unread treatment survives `markAllRead` (which flips
    /// `is_read` server-side) — matching the web's open-time snapshot.
    var unreadSnapshot: Set<String> = []

    /// Inline collab-request answers, by notification id ("accepted" /
    /// "declined"), and the ones in flight.
    private(set) var collabResults: [String: String] = [:]
    private(set) var respondingIds: Set<String> = []
    var respondError: String?

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
    }

    var unreadCount: Int { notifications.filter { !($0.isRead ?? false) }.count }

    /// Notifications passing the active chip.
    var filtered: [ApiNotification] {
        guard let filter else { return notifications }
        return notifications.filter { NotificationCategory.of($0.action) == filter }
    }

    /// The filtered feed bucketed: the open-time unread snapshot as "New",
    /// then by recency.
    var groups: [NotificationGroup] {
        let cal = Calendar.current
        let now = Date()
        let order = ["New", "Today", "Yesterday", "This week", "This month", "Older"]
        var buckets: [String: [ApiNotification]] = [:]
        for n in filtered {
            let title: String
            if unreadSnapshot.contains(n.id) {
                title = "New"
            } else {
                let date = MessageTime.parse(n.createdAt) ?? now
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
                switch days {
                case ..<1: title = "Today"
                case 1: title = "Yesterday"
                case ..<7: title = "This week"
                case ..<30: title = "This month"
                default: title = "Older"
                }
            }
            buckets[title, default: []].append(n)
        }
        return order.compactMap { title in
            buckets[title].map { NotificationGroup(id: title, title: title, items: $0) }
        }
    }

    /// A collab request still awaiting an answer from this row.
    func isPendingCollabRequest(_ n: ApiNotification) -> Bool {
        n.action == "requested collaboration" && n.contextType == "collaborator"
            && n.contextId != nil && collabResults[n.id] == nil
    }

    func collabResult(_ n: ApiNotification) -> String? { collabResults[n.id] }
    func isResponding(_ n: ApiNotification) -> Bool { respondingIds.contains(n.id) }

    /// Accepts / declines a collab request inline (`respond_to_collaborator`).
    /// Returns true on success so the caller can update the shared overlays.
    func respond(to n: ApiNotification, accept: Bool) async -> Bool {
        guard let relationshipId = n.contextId, !respondingIds.contains(n.id) else { return false }
        respondingIds.insert(n.id)
        respondError = nil
        defer { respondingIds.remove(n.id) }
        do {
            try await supabaseService.respondToCollaborator(relationshipId: relationshipId, accept: accept)
            collabResults[n.id] = accept ? "accepted" : "declined"
            return true
        } catch {
            debugLog("[NotificationsVM] respond: \(error)")
            // Already answered elsewhere (web / the thread) — reflect it
            // rather than leaving dead buttons.
            if error.serverRawDetail.contains("no longer pending") {
                collabResults[n.id] = "answered"
            } else {
                respondError = "Couldn't respond to the request. Try again."
            }
            return false
        }
    }

    func load() async {
        if notifications.isEmpty { loadingState = .loading }
        do {
            let items = try await supabaseService.getUserNotifications()
            notifications = items
            unreadSnapshot = Set(items.filter { !($0.isRead ?? false) }.map(\.id))
            loadingState = .loaded
            await markAllRead()
        } catch {
            debugLog("[NotificationsVM] load: \(error)")
            if notifications.isEmpty { loadingState = .error(error.localizedDescription) }
        }
    }

    func refresh() async {
        await load()
    }

    /// Flips read state server-side (and locally), but leaves `unreadSnapshot`
    /// intact so already-rendered highlights stay until the next reload.
    func markAllRead() async {
        guard !unreadSnapshot.isEmpty else { return }
        try? await supabaseService.markNotificationsRead()
        // Re-prime the coalesced unread-counts cache with post-mark truth, so
        // a passive refresh inside the 5s window can't resurrect the bell dot
        // the screen just optimistically cleared.
        _ = try? await supabaseService.getUnreadCounts(force: true)
    }

    /// "just now" / "5m" / "3h" / "2d" / date — mirrors the web's notification timeAgo.
    func timeAgo(_ iso: String) -> String {
        guard let date = MessageTime.parse(iso) else { return "" }
        let s = max(0, Int(Date().timeIntervalSince(date)))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        case ..<2592000: return "\(s / 86400)d"
        default: return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
