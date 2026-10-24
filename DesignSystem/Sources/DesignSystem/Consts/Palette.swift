//
//  Palette.swift
//  Volspire
//
//

import SwiftUI
import UIKit

public extension Color {
    /// Legacy alias of `Color.vBase` (ColorTokens.swift) — the themed page canvas.
    static let appBase = Color.vBase

    /// Legacy alias of `Color.vBar` (ColorTokens.swift) — the themed chrome tone.
    static let appBar = Color.vBar

    /// Legacy alias of `Color.vCard` (ColorTokens.swift) — ink @ 0.04 card fill.
    static let appCard = Color.vCard

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
    /// The accent as a `ShapeStyle` for send buttons and "already on" states.
    /// Now a SOLID #006BFC (`Color.vAccent`) — kept as a one-color gradient so
    /// every `LinearGradient.sendAccent` call site compiles unchanged.
    static let sendAccent = LinearGradient(
        colors: [Color.vAccent, Color.vAccent],
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
