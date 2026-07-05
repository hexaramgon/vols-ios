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

enum NotificationsLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

/// A recency bucket (Today / This Week / Earlier) for the grouped feed.
struct NotificationGroup: Identifiable {
    let id: String
    let title: String
    let items: [ApiNotification]
}

@Observable @MainActor
final class NotificationsScreenViewModel {
    var notifications: [ApiNotification] = []
    var loadingState: NotificationsLoadingState = .idle

    /// Ids that were unread when the screen opened. The UI highlights against
    /// this snapshot so the unread treatment survives `markAllRead` (which flips
    /// `is_read` server-side) — matching the web's open-time snapshot.
    var unreadSnapshot: Set<String> = []

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
    }

    var unreadCount: Int { notifications.filter { !($0.isRead ?? false) }.count }

    /// Notifications bucketed by recency for the grouped feed.
    var groups: [NotificationGroup] {
        let cal = Calendar.current
        let now = Date()
        var today: [ApiNotification] = []
        var week: [ApiNotification] = []
        var earlier: [ApiNotification] = []
        for n in notifications {
            let date = MessageTime.parse(n.createdAt) ?? now
            if cal.isDateInToday(date) {
                today.append(n)
            } else if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day, days < 7 {
                week.append(n)
            } else {
                earlier.append(n)
            }
        }
        var result: [NotificationGroup] = []
        if !today.isEmpty { result.append(NotificationGroup(id: "today", title: "Today", items: today)) }
        if !week.isEmpty { result.append(NotificationGroup(id: "week", title: "This Week", items: week)) }
        if !earlier.isEmpty { result.append(NotificationGroup(id: "earlier", title: "Earlier", items: earlier)) }
        return result
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
            print("[NotificationsVM] load: \(error)")
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
