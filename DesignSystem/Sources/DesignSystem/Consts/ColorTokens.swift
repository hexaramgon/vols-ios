//
//  ColorTokens.swift
//  DesignSystem
//
//  The app's semantic color tokens — one source of truth for every package and
//  the app target. Mirrors the web app's model: INK (text / icons / primary
//  fills) and CANVAS (page backgrounds) swap between light and dark, and the
//  neutral scale inverts. Every themed token resolves per trait collection, so
//  `.preferredColorScheme` / `.environment(\.colorScheme, .dark)` re-tint it.
//
//  Fixed tokens (accent, on-color labels, status reds/greens, shades over
//  artwork) deliberately do NOT theme.
//

import SwiftUI
import UIKit

// MARK: - Builders

public extension Color {
    /// A themed color: `dark` under a dark trait collection, `light` otherwise.
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: .dynamic(light: light, dark: dark))
    }

    /// INK at a fixed alpha in both modes — for fills (controls, cards, rows).
    static func ink(_ opacity: CGFloat) -> Color {
        .dynamic(light: Palette.inkLight.withAlphaComponent(opacity),
                 dark: Palette.inkDark.withAlphaComponent(opacity))
    }

    /// INK at a TEXT-tier alpha: `opacity` in dark, lifted in light so muted
    /// text keeps its contrast on white (`a' = 1 - (1 - a) * 0.65`, per the web
    /// app's light-mode scale).
    static func inkText(_ opacity: CGFloat) -> Color {
        .dynamic(light: Palette.inkLight.withAlphaComponent(1 - (1 - opacity) * 0.65),
                 dark: Palette.inkDark.withAlphaComponent(opacity))
    }
}

// MARK: - Themed tokens

public extension Color {
    // Canvas / chrome / surfaces (darkest → lightest in dark mode).

    /// Page canvas — every full-screen background. #0D0D0D / #FFFFFF.
    static let vBase = Color.dynamic(light: .white, dark: UIColor(white: 0.05, alpha: 1))
    /// The one chrome tone — headers, nav bars, the tab bar, collapsed title
    /// bars. A hair off the canvas. #121212 / #FAFAFA.
    static let vBar = Color.dynamic(light: UIColor(hex: 0xFAFAFA), dark: UIColor(white: 0.07, alpha: 1))
    /// Opaque card (≈ neutral-950) — settings groups, post cards, sheets,
    /// modals, menus. #141414 / #F5F5F5.
    static let vCardSolid = Color.dynamic(light: UIColor(hex: 0xF5F5F5), dark: UIColor(hex: 0x141414))
    /// Raised surface (≈ neutral-900) — pills, avatar fallbacks, skeleton
    /// bones, empty-state puck, incoming chat bubble. #1B1B1B / #ECECEC.
    static let vSurface = Color.dynamic(light: UIColor(hex: 0xECECEC), dark: UIColor(white: 0.105, alpha: 1))
    /// Higher surface (≈ neutral-800) — outgoing chat bubble, sheet header /
    /// footer rules, tab-bar top border (@0.8). #262626 / #E5E5E5.
    static let vSurface2 = Color.dynamic(light: UIColor(hex: 0xE5E5E5), dark: UIColor(hex: 0x262626))
    /// Hairline divider. One at a section's end, between settings rows —
    /// never per list row. Dark = neutral-900; light = translucent ink so the
    /// line darkens whatever it sits on (an opaque #ECECEC read as a WHITE
    /// line over the tinted profile hero and grey cards).
    static let vDivider = Color.dynamic(light: Palette.inkLight.withAlphaComponent(0.1),
                                        dark: UIColor(white: 0.105, alpha: 1))
    /// Skeleton-bone fill (= `vSurface`). Use with `Radius.tile`.
    static let vSkeleton = Color.vSurface
    /// Subtle translucent card / glassy-control fill (ink @ 0.04).
    static let vCard = Color.ink(0.04)
    /// Secondary-button / control fill (ink @ 0.08).
    static let vControl = Color.ink(0.08)
    /// Pressed / active control fill (ink @ 0.12).
    static let vControlActive = Color.ink(0.12)
    /// Selected list row (ink @ 0.05).
    static let vRowActive = Color.ink(0.05)
    /// Text-field fill at rest — white 0.11 / ink 0.06.
    static let vField = Color.dynamic(light: Palette.inkLight.withAlphaComponent(0.06),
                                      dark: UIColor(white: 1, alpha: 0.11))
    /// Text-field fill while focused — white 0.15 / ink 0.09.
    static let vFieldFocus = Color.dynamic(light: Palette.inkLight.withAlphaComponent(0.09),
                                           dark: UIColor(white: 1, alpha: 0.15))
    /// Modal backdrop — always black; 0.70 dark / 0.35 light.
    static let vScrim = Color.dynamic(light: UIColor(white: 0, alpha: 0.35), dark: UIColor(white: 0, alpha: 0.70))
    /// App-wide element outline. Clear by design — no decorative rings on
    /// pills, cards, avatars or fields.
    static let vBorder = Color.clear

    // Ink + text tiers.

    /// INK — primary text, icons, primary fills. #FFFFFF / #0D0D0D.
    static let vText = Color.dynamic(light: Palette.inkLight, dark: Palette.inkDark)
    /// Alias of `vText` for fills (`Color.vInk` reads better on a capsule).
    static let vInk = Color.vText
    /// List-row title at rest (ink 0.9 / 0.935) — near-full ink so track /
    /// folder names read crisply; the active row goes to full `vText`.
    static let vTextRow = Color.inkText(0.9)
    /// Secondary text / body (ink 0.64 / 0.766).
    static let vText2 = Color.inkText(0.64)
    /// Tertiary text / captions / inactive icons (ink 0.42 / 0.623).
    static let vText3 = Color.inkText(0.42)
    /// Disabled text (ink 0.25 / 0.5125).
    static let vText4 = Color.inkText(0.25)
    /// Secondary-button label (ink 0.70 / 0.805).
    static let vControlLabel = Color.inkText(0.70)

    /// Inverse fill — the PrimaryButton capsule / white pill (= ink).
    static let vInverse = Color.vText
    /// Label on `vInverse` — "paper": black in dark, white in light.
    static let vOnInverse = Color.dynamic(light: .white, dark: .black)
}

// MARK: - Fixed tokens (do not theme — status colours get a darker light variant for contrast)

public extension Color {
    /// The single accent — solid #006BFC. Send actions + "already on" states
    /// (Following, Collaborator) only.
    static let vAccent = Color(red: 0, green: 0x6B / 255, blue: 0xFC / 255)
    /// Labels on accent / red / green fills and text over artwork — always white.
    static let vOnColor = Color.white
    /// Labels on bright (amber) fills — #0D0D0D.
    static let vOnBright = Color(white: 0.05)
    /// Vignettes / shades over artwork — #0D0D0D, never themed.
    static let vShade = Color(white: 0.05)

    /// Error / failure text — web `text-red-400` (#F87171) in dark; red-600
    /// (#DC2626) in light, where red-400 on white is only ~2.8:1. Pair with
    /// `ErrorBanner` for inline errors.
    static let vError = Color.dynamic(light: UIColor(hex: 0xDC2626), dark: UIColor(hex: 0xF87171))
    /// A saved item's filled bookmark — the app's primary blue.
    static let vSaved = vAccent
    /// A rating's filled star — the app's red ("Top today") in light mode; in
    /// dark (and the always-dark player) a vivid red rather than vError's
    /// pale #F87171, which read muted there.
    static let vRating = Color.dynamic(light: UIColor(hex: 0xDC2626), dark: UIColor(hex: 0xFF453A))
    /// Error-banner fill — #450A0A @ 0.30 in dark; red-600 @ 0.08 in light
    /// (the dark wash turned muddy grey on white).
    static let vErrorFill = Color.dynamic(light: UIColor(hex: 0xDC2626).withAlphaComponent(0.08),
                                          dark: UIColor(hex: 0x450A0A).withAlphaComponent(0.30))
    /// Destructive-button fill — web `bg-red-600` (#DC2626).
    static let vDestructive = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
    /// Danger-soft fill — red-500 @ 0.10; pair with `vError` text.
    static let vDangerSoft = Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.10)
    /// Success fill — web `bg-emerald-600` (#059669).
    static let vSuccess = Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255)
    /// Success text — web `text-emerald-400` (#34D399) in dark; emerald-600
    /// (#059669) in light for contrast on white.
    static let vSuccessText = Color.dynamic(light: UIColor(hex: 0x059669), dark: UIColor(hex: 0x34D399))
    /// Owner / crown gold — #FFD700 in dark; yellow-700 (#A16207) in light,
    /// where it is used as label text.
    static let vOwnerGold = Color.dynamic(light: UIColor(hex: 0xA16207), dark: UIColor(red: 1, green: 0.84, blue: 0, alpha: 1))
    /// Unread / notification dot — web `bg-red-500` (#EF4444). Distinct from
    /// `vError` (red-400), which is for errors.
    static let vUnread = Color(red: 0.937, green: 0.267, blue: 0.267)
    /// Warning / caution — web `text-amber-500` (#F59E0B) in dark; amber-700
    /// (#B45309) in light, where it is used as text/glyph tint.
    static let vWarning = Color.dynamic(light: UIColor(hex: 0xB45309), dark: UIColor(hex: 0xF59E0B))
}

// MARK: - UIKit mirrors (UIAppearance proxies)

public extension UIColor {
    /// `Color.vBar` for UIKit appearance proxies.
    static let vBar = UIColor.dynamic(light: UIColor(hex: 0xFAFAFA), dark: UIColor(white: 0.07, alpha: 1))
    /// `Color.vSurface2` for UIKit appearance proxies.
    static let vSurface2 = UIColor.dynamic(light: UIColor(hex: 0xE5E5E5), dark: UIColor(hex: 0x262626))
    /// `Color.vText` for UIKit appearance proxies.
    static let vText = UIColor.dynamic(light: Palette.inkLight, dark: Palette.inkDark)
    /// `Color.vText3` for UIKit appearance proxies.
    static let vText3 = UIColor.dynamic(light: Palette.inkLight.withAlphaComponent(1 - 0.58 * 0.65),
                                        dark: Palette.inkDark.withAlphaComponent(0.42))
}

extension Palette {
    /// Ink in light mode (#0D0D0D) and dark mode (#FFFFFF).
    static let inkLight = UIColor(hex: 0x0D0D0D)
    static let inkDark = UIColor.white
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
