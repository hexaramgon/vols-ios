//
//  AppView.swift
//  Volspire
//
//

import DesignSystem
import Services
import SwiftUI

struct AppView: View {
    @Environment(Dependencies.self) var dependencies
    @Environment(\.scenePhase) private var scenePhase

    /// Minimum time the splash stays up so the logo is actually seen.
    @State private var minSplashElapsed = false

    /// Splash covers the launch + auth restore; it stays until the logo's had its
    /// moment AND auth has resolved (so the loading spinner never flashes through).
    private var showSplash: Bool {
        !minSplashElapsed || dependencies.authManager.state == .loading
    }

    var body: some View {
        ZStack {
            Group {
                switch dependencies.authManager.state {
                case .loading:
                    Color.vBase.ignoresSafeArea()
                case .authenticated:
                    OverlaidRootView()
                        .environment(dependencies.playerController)
                        .environment(\.managedObjectContext, dependencies.dataController.container.viewContext)
                case .unauthenticated:
                    LoginScreen()
                }
            }
            .preferredColorScheme(.dark)
            .environment(\.font, .geist(17, relativeTo: .body))
            // Smooth launch/auth transition (loading → app). Doesn't affect tab switching.
            .animation(.easeInOut(duration: 0.3), value: dependencies.authManager.state)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.45), value: showSplash)
        // Sign-out teardown: whenever an authenticated session ends (explicit
        // sign-out OR a server-revoked session), stop playback and drop all
        // per-user in-memory state so the next session starts clean.
        .onChange(of: dependencies.authManager.state) { old, new in
            if case .authenticated = old, case .unauthenticated = new {
                dependencies.resetForSignOut()
            }
            // Session became active (launch restore or fresh sign-in):
            // register this device for pushes. First run shows the system
            // permission prompt; afterwards this silently refreshes the token.
            if case .authenticated = new {
                Task { await PushNotificationManager.shared.enable() }
            }
        }
        // Opening the app clears the icon badge — the next push re-stamps it
        // with the true unread count (computed server-side).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                PushNotificationManager.shared.clearBadge()
            }
        }
        .task {
            await dependencies.authManager.restoreSession()
        }
        .task {
            await dependencies.authManager.listenForAuthChanges()
        }
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            minSplashElapsed = true
        }
    }
}
