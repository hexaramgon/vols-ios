//
//  NotificationsScreenViewModel.swift
//  Volspire
//
//

import Foundation
import Observation
import Services

enum NotificationsLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable @MainActor
final class NotificationsScreenViewModel {
    var notifications: [ApiNotification] = []
    var loadingState: NotificationsLoadingState = .idle

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
    }

    func loadNotifications() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading

        do {
            notifications = try await supabaseService.getUserNotifications()
            loadingState = .loaded
        } catch {
            print("[NotificationsVM] Failed to load notifications: \(error)")
            loadingState = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        loadingState = .idle
        await loadNotifications()
    }

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    // MARK: - Display Helpers

    func icon(for notification: ApiNotification) -> String {
        switch notification.action {
        case "follow": return "person.fill.badge.plus"
        case "like": return "heart.fill"
        case "comment": return "bubble.left.fill"
        case "download": return "arrow.down.circle.fill"
        case "release": return "music.note"
        case "feature": return "star.fill"
        case "collab": return "person.2.fill"
        default: return "bell.fill"
        }
    }

    func iconColor(for notification: ApiNotification) -> String {
        switch notification.action {
        case "follow": return "blue"
        case "like": return "pink"
        case "comment": return "green"
        case "download": return "purple"
        case "release": return "orange"
        case "feature": return "yellow"
        case "collab": return "blue"
        default: return "gray"
        }
    }

    func title(for notification: ApiNotification) -> String {
        switch notification.action {
        case "follow": return "New Follower"
        case "like": return "Track Liked"
        case "comment": return "New Comment"
        case "download": return "Download Complete"
        case "release": return "New Release"
        case "feature": return "Featured"
        case "collab": return "Collab Request"
        default: return "Notification"
        }
    }

    func subtitle(for notification: ApiNotification) -> String {
        let actorName = notification.actor?.username ?? "Someone"
        switch notification.action {
        case "follow": return "\(actorName) started following you"
        case "like": return "\(actorName) liked your track"
        case "comment": return "\(actorName) commented on your track"
        case "download": return "Your download is ready"
        case "release": return "\(actorName) dropped a new track"
        case "feature": return "Your track was featured"
        case "collab": return "\(actorName) wants to collaborate"
        default: return "\(actorName) interacted with your content"
        }
    }

    func relativeTime(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: dateString) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateString)
        }()
        guard let date else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: .now)
    }
}
