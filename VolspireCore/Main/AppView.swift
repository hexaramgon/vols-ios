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

    /// Minimum time the splash holds before its exit, so the logo is seen.
    @State private var minSplashElapsed = false
    /// The splash's exit animation has finished — it's removed.
    @State private var splashFinished = false

    /// The splash covers the launch + auth restore; its spear-thrust exit
    /// starts once the logo's had its moment AND auth has resolved (so the
    /// loading state never flashes through).
    private var splashReady: Bool {
        minSplashElapsed && dependencies.authManager.state != .loading
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
                        .environment(dependencies.libraryStore)
                        .environment(dependencies.workspaceStore)
                        .environment(dependencies.socialStore)
                        .environment(dependencies.inboxStore)
                        .environment(dependencies.listingsStore)
                        .environment(dependencies.feedStore)
                        .environment(dependencies.packsStore)
                case .needsProfile:
                    // Signed in with no profile row — finish the account before
                    // the app opens (see AuthManager.AuthState.needsProfile).
                    CompleteProfileScreen()
                case .unauthenticated:
                    LoginScreen()
                }
            }
            .appAppearance()
            // Feeds ViewConst.safeAreaInsets (never read from UIKit in a body).
            .measuresSafeArea()
            .environment(\.font, .geist(17, relativeTo: .body))
            // App-wide: tapping inert space drops the keyboard (fields/buttons
            // still win their taps). Sheets get it via sheetBackground();
            // full-screen covers apply it to their own roots.
            .tapToDismissKeyboard()
            // Smooth launch/auth transition (loading → app). Doesn't affect tab switching.
            .animation(.easeInOut(duration: 0.3), value: dependencies.authManager.state)

            // Runs its own exit (thrust + fade); removed once it's done.
            if !splashFinished {
                VolspireSplashView(isReady: splashReady) { splashFinished = true }
                    .zIndex(10)
            }
        }
        // Sign-out teardown: whenever an authenticated session ends (explicit
        // sign-out OR a server-revoked session), stop playback and drop all
        // per-user in-memory state so the next session starts clean.
        .onChange(of: dependencies.authManager.state) { old, new in
            if case .authenticated = old, case .unauthenticated = new {
                dependencies.resetForSignOut()
            }
            // Session became active (launch restore or fresh sign-in):
            // refresh this device's push token if permission is granted. The
            // permission prompt itself comes from the push primer (RootTabView)
            // or Settings → Notifications, never straight from sign-in.
            if case .authenticated = new {
                Task { await PushNotificationManager.shared.enable() }
            }
        }
        .task {
            await dependencies.authManager.restoreSession()
        }
        .task {
            await dependencies.authManager.listenForAuthChanges()
        }
        .task {
            try? await Task.sleep(for: .seconds(0.6))
            minSplashElapsed = true
        }
    }
}
