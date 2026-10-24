//
//  UIScreen+Extensions.swift
//  Volspire
//
//

import UIKit

public extension UIScreen {
    /// The screen the app is actually drawing on. `UIScreen.main` is deprecated
    /// as of iOS 26 (it presumes a single display), so resolve through the
    /// active window scene instead, falling back to any connected one.
    private static var active: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen
    }

    /// Pixels per point — used to size downsampled image buffers. The fallback
    /// is unreachable in practice (UI code always runs with a window scene) and
    /// only ever costs a slightly-off decode size, never a layout change.
    static var displayScale: CGFloat {
        active?.scale ?? 3
    }

    /// The display's corner radius, so the now-playing card's corners can meet
    /// the screen's as it settles into place.
    ///
    /// This used to read the private `_displayCornerRadius` key by KVC — exact,
    /// but non-public API, which App Review guideline 2.5.1 prohibits outright.
    /// Public API can't report the radius, so it's derived instead: devices with
    /// a home indicator have rounded displays, home-button devices (SE) are
    /// square, and the radius itself keys off the screen width. Being a couple
    /// of points off on an unlisted device is purely cosmetic — the card's
    /// corners sit a hair inside or outside the display's.
    static var deviceCornerRadius: CGFloat {
        // No home indicator ⇒ square display (SE family). Rounding those corners
        // would float the card's arcs against flat screen edges.
        let hasHomeIndicator = (UIApplication.keyWindow?.safeAreaInsets.bottom ?? 0) > 0
        guard hasHomeIndicator else { return 0 }

        switch round(size.width) {
        case 375: return 44 // 12/13 mini, X/XS/11 Pro
        case 390: return 47.33 // 12, 13, 14
        case 393: return 55 // 14 Pro, 15, 16
        case 402: return 62 // 16 Pro, 17
        case 414: return 41.5 // XR, 11, XS Max, 11 Pro Max
        case 428: return 53.33 // 12/13 Pro Max, 14 Plus
        case 430: return 55 // 14 Pro Max, 15 Plus/Pro Max, 16 Plus
        case 440: return 62 // 16 Pro Max, 17 Pro Max
        default: return 55 // sane modern default for anything unlisted
        }
    }

    static var hairlineWidth: CGFloat {
        1 / displayScale
    }

    /// Deliberately still `UIScreen.main`, and deliberately a stored `let`:
    /// every layout in the app is measured against this, and on iPad the app
    /// runs in iPhone compatibility mode, where `main` reports the emulated
    /// iPhone screen. Sourcing it from the window scene instead risks handing
    /// back the real iPad bounds and stretching every screen. Migrating it
    /// needs a physical iPad check, not a compile-clean swap.
    static let size = UIScreen.main.bounds.size
}
