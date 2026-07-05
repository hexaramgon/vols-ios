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

/// The notification toggles surfaced in Settings (mirrors the web's
/// `notificationItems`). `messages` is preserved by the RPC but not shown here.
enum NotificationPref: String, CaseIterable, Identifiable {
    case newFollowers = "new_followers"
    case likes
    case saves
    case comments
    case shares
    case purchases
    case uploads
    case collaborations
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newFollowers: "New followers"
        case .likes: "Likes"
        case .saves: "Saves"
        case .comments: "Comments"
        case .shares: "Shares"
        case .purchases: "Purchases"
        case .uploads: "New uploads"
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
        case .shares: "When someone shares your track"
        case .purchases: "When someone buys a track, pack, or books a service"
        case .uploads: "When an artist you follow uploads new music"
        case .collaborations: "When someone wants to collaborate"
        case .folders: "When you're added to or shared a folder"
        }
    }
}

@Observable @MainActor
final class SettingsViewModel {
    private(set) var prefs: [String: Bool] = [:]
    private(set) var prefsLoaded = false
    var prefsError: String?

    // Account summary for the settings header.
    private(set) var accountUsername = ""
    private(set) var accountAvatarURL: URL?
    private(set) var accountType: String?
    private(set) var accountLoaded = false

    private let service: SupabaseService

    init(service: SupabaseService = SupabaseService()) {
        self.service = service
    }

    func isOn(_ pref: NotificationPref) -> Bool {
        prefs[pref.rawValue] ?? true
    }

    /// Loads the signed-in user's name + avatar for the settings header.
    func loadAccount(userId: String?) async {
        guard let userId, !userId.isEmpty else { return }
        do {
            let profile = try await service.getUserProfile(userId: userId)
            accountUsername = profile.username ?? ""
            accountAvatarURL = profile.profileImageUrl.flatMap { URL(string: $0) }
            accountType = profile.accountType
        } catch {
            print("[SettingsVM] Failed to load account: \(error)")
        }
        accountLoaded = true
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
            print("[SettingsVM] Failed to load notification prefs: \(error)")
        }
    }

    /// Optimistically flips a toggle, rolling back if the RPC fails.
    func toggle(_ pref: NotificationPref, to value: Bool) async {
        let previous = prefs[pref.rawValue] ?? true
        prefs[pref.rawValue] = value
        prefsError = nil
        do {
            prefs = Self.dictionary(from: try await service.updateNotificationPreference(key: pref.rawValue, value: value))
        } catch {
            prefs[pref.rawValue] = previous
            prefsError = "Couldn't save. Try again."
            print("[SettingsVM] Failed to update notification pref: \(error)")
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
