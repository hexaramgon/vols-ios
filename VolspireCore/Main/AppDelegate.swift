//
//  AppDelegate.swift
//  Volspire
//
//

import Services
import UIKit
import UserNotifications

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
        print("[Push] APNs registration failed: \(error)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show pushes as banners while the app is open too (no sound in-app).
    /// Touches no state — safe off the main actor.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge]
    }
}
