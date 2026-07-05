//
//  GeistFont.swift
//  DesignSystem
//
//  Bundles + registers the web app's typeface (Geist) and exposes a helper.
//  The static weights ship as separate families, so we address faces by their
//  exact PostScript names rather than family + `.weight()`.
//

import CoreText
import SwiftUI

public enum GeistFont {
    static let faces = ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold"]
    nonisolated(unsafe) private static var registered = false

    /// Registers the bundled Geist faces for the process. Call once at launch.
    public static func register() {
        guard !registered else { return }
        registered = true
        for face in faces {
            guard let url = Bundle.module.url(forResource: face, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// PostScript name for the closest bundled weight.
    static func psName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Geist-Bold"
        case .semibold: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
    }
}

public extension Font {
    /// Geist (the web app's typeface) at an explicit size + weight, Dynamic Type-aware.
    static func geist(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(GeistFont.psName(for: weight), size: size, relativeTo: textStyle)
    }
}
