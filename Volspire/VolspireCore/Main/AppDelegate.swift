//
//  AppDelegate.swift
//  Volspire
//
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var dependencies: Dependencies?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        dependencies = .make()
        return true
    }
}
