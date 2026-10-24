//
//  AppAppearance.swift
//  Volspire
//
//  The user's theme choice (Settings → Appearance → Theme). Persisted under the
//  `appearance` AppStorage key, default `.system`, and applied ONCE at the root
//  (`AppView`) via `.appAppearance()` — sheets and full-screen covers live in
//  the same window, so they follow it too. Content that must stay dark in
//  light mode (Now Playing, the profile banner hero) scopes `.alwaysDark()`.
//

import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    /// The `@AppStorage` key the choice persists under.
    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` follows the device setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct AppAppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    /// The scheme ABOVE `.preferredColorScheme` — i.e. the device setting.
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            // `.preferredColorScheme(nil)` doesn't reliably hand control back
            // to the system once a scheme was forced, so also drive the windows'
            // override directly — that reaches presented sheets/covers too.
            .onChange(of: appearance, initial: true) { _, newValue in
                forEachWindow { $0.overrideUserInterfaceStyle = newValue.interfaceStyle }
                refreshStatusBar()
            }
            // A live device appearance flip re-tints the views but the status
            // bar kept its old style (white on white) until the next
            // interaction — ask every controller in the chain to re-query it.
            .onChange(of: systemScheme) { refreshStatusBar() }
    }

    private func forEachWindow(_ body: (UIWindow) -> Void) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach(body)
        }
    }

    /// Next run-loop turn, so the trait change has reached the controllers.
    private func refreshStatusBar() {
        Task { @MainActor in
            forEachWindow { window in
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsStatusBarAppearanceUpdate()
                    controller = current.presentedViewController
                }
            }
        }
    }
}

extension View {
    /// Applies the persisted `AppAppearance` — call once, at the app root.
    func appAppearance() -> some View {
        modifier(AppAppearanceModifier())
    }
}
