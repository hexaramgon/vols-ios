//
//  AppDelegate.swift
//  Volspire
//
//

import Services
import UIKit
import UserNotifications
import SharedUtilities

class AppDelegate: NSObject, UIApplicationDelegate {
    var dependencies: Dependencies?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        dependencies = .make()   // configures the uploads' backend
        // Before UIKit hands over background events: reconnects the uploads'
        // session, so a relaunch receives them.
        BackgroundUploads.shared.activate()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// The system relaunched the app for finished background uploads.
    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        nonisolated(unsafe) let completion = completionHandler
        BackgroundUploads.shared.handleEvents(identifier: identifier) { completion() }
    }

    // MARK: - APNs registration

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        debugLog("[Push] APNs registration failed: \(error)")
    }
}

// Completion-handler forms ON PURPOSE, both completing on the main queue: the
// `async` variants resume on a background executor after their last await, so
// the bridged UIKit completion ran off-main — and when the app is launched
// from a lock-screen tap, that completion performs snapshot/state-restoration
// work that asserts main-thread. That assertion was a TestFlight crash
// (SIGABRT in `_updateStateRestorationArchiveForBackgroundEvent`, ~200ms
// after launch). Don't convert these back to `async`.
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// While the app is open, pushes show as the app's OWN banner
    /// (PushBannerHost) — not the system's, which iOS hides under a Focus /
    /// banner-style setting — and still land in Notification Center. Except
    /// messages for the conversation already on screen: nothing at all.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let userInfo = content.userInfo
        let convoId = userInfo["convo_id"] as? String
        var info: [String: String] = ["title": content.title, "body": content.body]
        for (key, value) in userInfo {
            if let k = key as? String, let v = value as? String { info[k] = v }
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // Something new happened server-side — the in-app dots, the
                // inbox rows and an open Notifications page catch up now
                // instead of at the next tab switch / foreground.
                NotificationCenter.default.post(name: .pushReceived, object: nil, userInfo: info)
                let visible = PushNotificationManager.shared.visibleConversationId
                let isOnScreen = convoId != nil && convoId?.caseInsensitiveCompare(visible ?? "") == .orderedSame
                if !isOnScreen { PushBannerCenter.shared.show(info) }
                completionHandler(isOnScreen ? [] : [.list, .badge])
            }
        }
    }

    /// A tapped notification (lock screen / banner) — buffer its data and signal
    /// RootTabView to deep-link to the entity it references.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let content = response.notification.request.content
        var info: [String: String] = ["title": content.title]
        for (key, value) in content.userInfo {
            if let k = key as? String, let v = value as? String { info[k] = v }
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                PushInbox.pending = info
                NotificationCenter.default.post(name: .openPushNotification, object: nil)
            }
            completionHandler()
        }
    }
}
