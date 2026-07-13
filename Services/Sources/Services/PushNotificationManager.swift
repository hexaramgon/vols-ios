//
//  PushNotificationManager.swift
//  Services
//
//  APNs registration + token sync. `enable()` (called when a session becomes
//  active) asks for permission and registers with Apple; the AppDelegate
//  forwards the resulting device token to `didRegister`, which upserts it into
//  `user_push_tokens` via the `register_push_token` RPC. Sign-out deactivates
//  the token server-side (best-effort) before the session is dropped.
//

import Supabase
import UIKit
import UserNotifications

@MainActor
public final class PushNotificationManager {
    public static let shared = PushNotificationManager()

    private let client: SupabaseClient
    /// The APNs device token (hex) Apple last handed us — kept so sign-out can
    /// deactivate it server-side.
    private(set) var currentToken: String?

    public init(client: SupabaseClient = supabaseClient) {
        self.client = client
    }

    /// Ask for notification permission (the system prompt appears only the
    /// first time) and register with APNs. Call whenever a session becomes
    /// active — later calls are silent and just refresh the token.
    public func enable() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// APNs token from the AppDelegate callback — uploads it for the current
    /// account.
    public func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        Task { await upload(token: token) }
    }

    private func upload(token: String) async {
        // Tokens can only be registered against a session.
        guard client.auth.currentSession != nil else { return }
        do {
            try await client
                .rpc("register_push_token", params: [
                    "p_token": token,
                    "p_platform": "ios",
                    "p_device_name": UIDevice.current.name,
                ])
                .execute()
        } catch {
            print("[Push] register_push_token failed: \(error)")
        }
    }

    /// Clears the app-icon badge — called when the app comes to the
    /// foreground (the user is looking at the app; the next push re-stamps
    /// the true unread count computed server-side).
    public func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Best-effort: stop pushes to this device for the signing-out account.
    /// Must run BEFORE the local session is dropped (the RPC needs auth).
    public func deactivateForSignOut() async {
        guard let token = currentToken, client.auth.currentSession != nil else { return }
        do {
            try await client
                .rpc("deactivate_push_token", params: ["p_token": token])
                .execute()
        } catch {
            print("[Push] deactivate_push_token failed: \(error)")
        }
    }
}
