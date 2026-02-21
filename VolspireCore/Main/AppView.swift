//
//  AppView.swift
//  Volspire
//
//

import Services
import SwiftUI

struct AppView: View {
    @Environment(Dependencies.self) var dependencies

    var body: some View {
        Group {
            switch dependencies.authManager.state {
            case .loading:
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    ProgressView()
                }
            case .authenticated:
                OverlaidRootView()
                    .environment(dependencies.playerController)
                    .environment(\.managedObjectContext, dependencies.dataController.container.viewContext)
            case .unauthenticated:
                LoginScreen()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: dependencies.authManager.state)
        .task {
            await dependencies.authManager.restoreSession()
        }
        .task {
            await dependencies.authManager.listenForAuthChanges()
        }
    }
}
