//
//  SettingsViewModel.swift
//  Volspire
//
//  Loads + toggles the user's notification preferences (mirrors the web
//  settings page, backed by get/update_notification_preferences).
//

import Foundation
import Observation
import Services
import SharedUtilities

/// The notification toggles surfaced in Settings — only ones a push actually
/// checks (notify_activity_targets / notify_message_targets). `shares` and
/// `uploads` exist in the table but nothing pushes for them, so they're not
/// shown; their values are still round-tripped.
enum NotificationPref: String, CaseIterable, Identifiable {
    case newFollowers = "new_followers"
    case likes
    case saves
    case comments
    case messages
    case collaborations
    case folders
    case purchases

    var id: String { rawValue }

    /// The rows Settings actually shows. `purchases` is hidden while
    /// monetization is off (FeatureFlags.marketplace) — nothing in the app can
    /// be bought, so a toggle for sale alerts advertises a feature that isn't
    /// there. The pref itself is still round-tripped to the server, so a user's
    /// choice survives until the marketplace ships.
    static var visibleCases: [NotificationPref] {
        allCases.filter { FeatureFlags.marketplace || $0 != .purchases }
    }

    var title: String {
        switch self {
        case .newFollowers: "New followers"
        case .likes: "Likes"
        case .saves: "Saves"
        case .comments: "Comments"
        case .messages: "Messages"
        case .purchases: "Purchases"
        case .collaborations: "Collaborations"
        case .folders: "Folders"
        }
    }

    var subtitle: String {
        switch self {
        case .newFollowers: "When someone follows your profile"
        case .likes: "When someone likes your track"
        case .saves: "When someone saves your track"
        case .comments: "When someone comments on your posts"
        case .messages: "When someone messages you or responds to your listing"
        case .purchases: "When someone buys a track, pack, or books a service"
        case .collaborations: "When someone wants to collaborate"
        case .folders: "When you're added to or shared a folder"
        }
    }
}

@Observable @MainActor
final class SettingsViewModel {
    private(set) var prefs: [String: Bool] = [:]
    private(set) var prefsLoaded = false
    /// Set when a toggle failed to save (and was rolled back).
    private(set) var saveError: String?

    private let service: SupabaseService

    init(service: SupabaseService = SupabaseService()) {
        self.service = service
    }

    func isOn(_ pref: NotificationPref) -> Bool {
        prefs[pref.rawValue] ?? true
    }

    func loadPreferences() async {
        do {
            prefs = Self.dictionary(from: try await service.getNotificationPreferences())
            prefsLoaded = true
        } catch {
            // Default everything on if the fetch fails (matches the web).
            if !prefsLoaded {
                prefs = Dictionary(uniqueKeysWithValues: NotificationPref.allCases.map { ($0.rawValue, true) })
                prefsLoaded = true
            }
            debugLog("[SettingsVM] Failed to load notification prefs: \(error)")
        }
    }

    /// Optimistically flips a toggle, rolling back if the RPC fails.
    func toggle(_ pref: NotificationPref, to value: Bool) async {
        let previous = prefs[pref.rawValue] ?? true
        prefs[pref.rawValue] = value
        saveError = nil
        do {
            prefs = Self.dictionary(from: try await service.updateNotificationPreference(key: pref.rawValue, value: value))
        } catch {
            prefs[pref.rawValue] = previous
            saveError = "Could not save. Try again."
            debugLog("[SettingsVM] Failed to update notification pref: \(error)")
        }
    }

    private static func dictionary(from prefs: ApiNotificationPreferences) -> [String: Bool] {
        let keys = ["new_followers", "likes", "saves", "comments", "shares",
                    "purchases", "uploads", "collaborations", "folders", "messages"]
        return keys.reduce(into: [:]) { dict, key in
            if let value = prefs.value(for: key) { dict[key] = value }
        }
    }
}
