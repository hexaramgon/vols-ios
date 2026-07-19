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
        dependencies = .make()
        UNUserNotificationCenter.current().delegate = self
        return true
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
    /// Show pushes as banners while the app is open too (no sound in-app).
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async { completionHandler([.banner, .badge]) }
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
