//
//  PushNotificationManager.swift
//  Services
//
//  APNs registration + token sync. `enable()` (called when a session becomes
//  active) registers with Apple only if permission was already granted; the
//  system prompt comes from `requestPermission()`, which the app calls after
//  its own explanation (the push primer) or from Settings. The AppDelegate
//  forwards the device token to `didRegister`, which upserts it into
//  `user_push_tokens` via the `register_push_token` RPC. Sign-out deactivates
//  the token server-side (best-effort) before the session is dropped.
//

import Observation
import SharedUtilities
import Supabase
import UIKit
import UserNotifications

@MainActor @Observable
public final class PushNotificationManager {
    public static let shared = PushNotificationManager()

    @ObservationIgnored private let client: SupabaseClient
    /// The APNs device token (hex) Apple last handed us — kept so sign-out can
    /// deactivate it server-side.
    @ObservationIgnored private(set) var currentToken: String?

    /// The system notification permission, as of the last `refreshStatus()`.
    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The conversation currently on screen. Its message pushes aren't shown
    /// as banners while the app is open (see the AppDelegate's `willPresent`).
    @ObservationIgnored public var visibleConversationId: String?

    public init(client: SupabaseClient = supabaseClient) {
        self.client = client
    }

    /// Registers with APNs if permission is already granted. Never shows the
    /// system prompt. Call whenever a session becomes active — it just
    /// refreshes the token.
    public func enable() async {
        await refreshStatus()
        if canNotify { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Shows the system permission prompt (iOS only shows it while the status
    /// is `.notDetermined`) and registers with APNs if granted.
    @discardableResult
    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    public func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var canNotify: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
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
                    "p_device_name": Self.deviceModel,
                ])
                .execute()
        } catch {
            debugLog("[Push] register_push_token failed: \(error)")
        }
    }

    /// Hardware model identifier (e.g. "iPhone16,1") — a non-identifying device label.
    /// Replaces `UIDevice.current.name`, which is the user-set device name (often their
    /// real name, e.g. "Hector's iPhone") and is PII we shouldn't persist server-side.
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let model = withUnsafePointer(to: &info.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return model.isEmpty ? UIDevice.current.model : model
    }

    /// Clears the app-icon badge — called when the app comes to the
    /// foreground (the user is looking at the app; the next push re-stamps
    /// the true unread count computed server-side).
    public func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Removes already-delivered notifications for a conversation from Notification
    /// Center — call when the user opens that conversation so its alerts don't
    /// linger. The message push payload carries `convo_id` in its userInfo.
    public func clearDeliveredNotifications(convoId: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { ($0.request.content.userInfo["convo_id"] as? String) == convoId }
                .map(\.request.identifier)
            guard !ids.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Stamps the app-icon badge. The count comes from InboxStore's single
    /// `get_unread_counts` pipeline — this manager no longer fetches it itself
    /// (it used to make a duplicate RPC through its own client).
    public func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count))
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
            debugLog("[Push] deactivate_push_token failed: \(error)")
        }
    }
}
