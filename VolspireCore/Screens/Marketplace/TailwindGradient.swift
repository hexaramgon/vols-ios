//
//  TailwindGradient.swift
//  Volspire
//
//  The web app stores a per-pack/service gradient as a Tailwind class string in
//  the DB `gradient` column (e.g. "from-violet-900 via-violet-950 to-black").
//  This renders that string as SwiftUI colours so a cover with no uploaded image
//  shows the same colourful gradient the web does instead of flat grey.
//

import SwiftUI

enum TailwindGradient {
    /// Ordered colours for a top-leading → bottom-trailing gradient, or nil when
    /// the string is empty or unparseable (callers fall back to a neutral wash).
    static func colors(from string: String?) -> [Color]? {
        guard let string, !string.isEmpty else { return nil }
        let stops = string.split(separator: " ").compactMap { token -> Color? in
            for prefix in ["from-", "via-", "to-"] where token.hasPrefix(prefix) {
                return color(String(token.dropFirst(prefix.count)))
            }
            return nil
        }
        return stops.count >= 2 ? stops : nil
    }

    /// One Tailwind colour token → Color, e.g. "violet-900", "black", "blue-900/80".
    /// Internal so single-swatch callers (gradient pickers, service covers) resolve
    /// against this canonical palette instead of hand-converting rgb.
    static func color(_ token: String) -> Color? {
        var name = token
        var opacity = 1.0
        if let slash = name.firstIndex(of: "/") {
            opacity = (Double(name[name.index(after: slash)...]) ?? 100) / 100
            name = String(name[..<slash])
        }
        switch name {
        case "black": return Color.black.opacity(opacity)
        case "white": return Color.white.opacity(opacity)
        case "transparent": return Color.clear
        default:
            guard let hex = palette[name] else { return nil }
            return rgb(hex).opacity(opacity)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Tailwind v3 palette — the hues/shades that appear in marketplace gradients.
    private static let palette: [String: UInt32] = [
        "neutral-200": 0xE5E5E5, "neutral-400": 0xA3A3A3, "neutral-700": 0x404040,
        "neutral-800": 0x262626, "neutral-900": 0x171717, "neutral-950": 0x0A0A0A,
        "gray-800": 0x1F2937, "gray-900": 0x111827, "gray-950": 0x030712,
        "slate-800": 0x1E293B, "slate-900": 0x0F172A, "slate-950": 0x020617,
        "red-800": 0x991B1B, "red-900": 0x7F1D1D, "red-950": 0x450A0A,
        "orange-800": 0x9A3412, "orange-900": 0x7C2D12, "orange-950": 0x431407,
        "amber-800": 0x92400E, "amber-900": 0x78350F, "amber-950": 0x451A03,
        "yellow-800": 0x854D0E, "yellow-900": 0x713F12, "yellow-950": 0x422006,
        "green-800": 0x166534, "green-900": 0x14532D, "green-950": 0x052E16,
        "emerald-800": 0x065F46, "emerald-900": 0x064E3B, "emerald-950": 0x022C22,
        "teal-800": 0x115E59, "teal-900": 0x134E4A, "teal-950": 0x042F2E,
        "cyan-800": 0x155E75, "cyan-900": 0x164E63, "cyan-950": 0x083344,
        "sky-800": 0x075985, "sky-900": 0x0C4A6E, "sky-950": 0x082F49,
        "blue-800": 0x1E40AF, "blue-900": 0x1E3A8A, "blue-950": 0x172554,
        "indigo-800": 0x3730A3, "indigo-900": 0x312E81, "indigo-950": 0x1E1B4B,
        "violet-800": 0x5B21B6, "violet-900": 0x4C1D95, "violet-950": 0x2E1065,
        "purple-800": 0x6B21A8, "purple-900": 0x581C87, "purple-950": 0x3B0764,
        "fuchsia-900": 0x701A75, "fuchsia-950": 0x4A044E,
        "pink-800": 0x9D174D, "pink-900": 0x831843, "pink-950": 0x500724,
        "rose-800": 0x9F1239, "rose-900": 0x881337, "rose-950": 0x4C0519,
    ]
}
