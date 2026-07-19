//
//  Palette.swift
//  Volspire
//
//

import SwiftUI
import UIKit

public extension Color {
    /// The app's single dark base background — every full-screen background
    /// (`Color.vBase` in the app target, `.gradientBackground()` here) should
    /// point at this one value so they can never drift apart again.
    static let appBase = Color(white: 0.05)

    /// The app's single chrome tone (~#121212) — headers, nav bars, the tab
    /// bar, and collapsing title bars. A hair lighter than `appBase` so chrome
    /// reads as distinct from the page. Every bar background should point at
    /// this one value (`Color.vBar` in the app target).
    static let appBar = Color(white: 0.07)

    /// Subtle translucent fill for cards and glassy controls over dark pages —
    /// the empty-state CTA-card tone. Profile hero cards/buttons and the
    /// "No … yet" cards share it (`Color.vCard` in the app target).
    static let appCard = Color.white.opacity(0.04)

    static let spectrum: [Color] = [
        Color("AppCoral", bundle: .module),
        Color("AppOrange", bundle: .module),
        Color("AppYellow", bundle: .module),
        Color("AppLime", bundle: .module),
        Color("AppMint", bundle: .module),
        Color("AppSky", bundle: .module),
        Color("AppIndigo", bundle: .module),
        Color("AppPurple", bundle: .module),
        Color("AppPink", bundle: .module)
    ]

    static let iconSecondary: Color = .graySecondary

    static let textAccent: Color = .brand
    static let brand: Color = .init("Brand", bundle: .module)
    static let graySecondary: Color = .init("GraySecondary", bundle: .module)
}

public extension LinearGradient {
    /// Brand-led blue accent for composer send buttons (chat input + player
    /// comments) so every "send" reads as one family. White icons stay legible.
    static let sendAccent = LinearGradient(
        colors: [Color.brand, Color(red: 0.16, green: 0.40, blue: 0.86)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

public enum Palette {
    public enum PlayerCard {}
}

public extension Palette {
    static var playerCard: Palette.PlayerCard.Type {
        Palette.PlayerCard.self
    }

    static let artworkBorder: UIColor = .dynamic(
        light: .black.withAlphaComponent(0.2),
        dark: .white.withAlphaComponent(0.2)
    )

    static let artworkBackground: UIColor = .dynamic(
        light: UIColor(r: 233, g: 233, b: 234, a: 255),
        dark: UIColor(r: 39, g: 39, b: 41, a: 255)
    )

    static let buttonBackground: UIColor = .dynamic(
        light: UIColor(r: 238, g: 238, b: 239, a: 255),
        dark: UIColor(r: 28, g: 28, b: 31, a: 255)
    )

    static let textSecondary: UIColor = .dynamic(
        light: UIColor(r: 138, g: 138, b: 142, a: 255),
        dark: UIColor(r: 141, g: 141, b: 147, a: 255)
    )

    static let textTertiary: UIColor = .dynamic(
        light: UIColor(r: 127, g: 127, b: 127, a: 255),
        dark: UIColor(r: 128, g: 128, b: 128, a: 255)
    )
}

public extension Palette.PlayerCard {
    static let opaque: UIColor = .white
    static let translucent: UIColor = .init(white: 0.784, alpha: 0.816)
    static let artworkBackground: UIColor = .dynamic(
        light: Palette.platinum,
        dark: Palette.taupeGray
    )
}

private extension Palette {
    static let taupeGray = UIColor(red: 0.525, green: 0.525, blue: 0.545, alpha: 1)
    static let platinum = UIColor(red: 0.898, green: 0.898, blue: 0.913, alpha: 1)
}

public extension UIColor {
    static var palette: Palette.Type {
        Palette.self
    }
}
