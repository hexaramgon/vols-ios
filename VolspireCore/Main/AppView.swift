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
