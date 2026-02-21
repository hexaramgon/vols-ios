//
//  VolspireApp.swift
//  Volspire
//
//

import SwiftUI

@main
struct VolspireApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(appDelegate.dependencies)
                .onOpenURL { url in
                    Task {
                        await appDelegate.dependencies?.authManager.handleOAuthCallback(url: url)
                    }
                }
        }
    }
}
