//
//  ViewConst.swift
//  Volspire
//
//

import Foundation
import SwiftUI

public enum ViewConst {}

public extension ViewConst {
    static let playerCardPaddings: CGFloat = 24
    /// App-wide horizontal screen margin for headers, text, lists and rails.
    static let screenPaddings: CGFloat = 16
    /// Tighter horizontal edge padding for card/listing grids, so 2-column grids
    /// still fill a bit more of the screen than text content.
    static let gridPaddings: CGFloat = 8
    /// Header action-icon glyph size (bell / search / messages / "…" in header
    /// rows), used app-wide.
    static let headerIconSize: CGFloat = 26
    /// A header action's tap target (HeaderIconButton) — also the title row's
    /// height, so a header with no actions is as tall as one with them.
    static let headerButtonSize: CGFloat = 42
    /// THE "…" options-glyph size, app-wide — hero overlays, bar headers, and
    /// row accessories all draw the ellipsis at this one size (larger than
    /// `headerIconSize` so it holds its own next to the `backIconSize` chevron).
    static let heroOverlayIconSize: CGFloat = 28
    /// Back-chevron glyph size in pushed-screen nav bars. NB: the shared
    /// BackButton draws a Lucide chevron, whose inner viewBox padding makes it
    /// read ~25% smaller than an SF symbol at the same point size — this value
    /// is chosen for the Lucide rendering.
    static let backIconSize: CGFloat = 32
    static let compactNowPlayingHeight: CGFloat = 56
    /// Height of the screen header band (title / back row) — the web's 53px
    /// header. Background canvas @0.7 + blur (or opaque `vBar`), bottom
    /// hairline `vDivider`.
    static let headerBandHeight: CGFloat = 53

    /// The window's safe-area insets, as SwiftUI measured them at the app
    /// root (`measuresSafeArea()`). Never read from UIKit here: this is called
    /// from view bodies, and `UIWindow.safeAreaInsets` asks the hosting
    /// controller about the status bar, which re-enters the view graph
    /// mid-update — an AttributeGraph cycle that froze whole overlays (intro
    /// tips drew their dim with no content on launches from a stored session).
    /// Observable, so bodies that read it update once it's measured.
    static var safeAreaInsets: EdgeInsets {
        MainActor.assumeIsolated { SafeAreaStore.shared.insets }
    }
}

/// The app's corner-radius scale — snap ad-hoc radii to these (9/10/11 →
/// `tile`/`card`, 14 → `card` or `panel`). Buttons and accent pills use
/// `Capsule()` instead.
public enum Radius {
    /// 8 — thumbnails, chips, skeleton bones, icon tiles.
    public static let tile: CGFloat = 8
    /// 12 — cards, inputs, rows, alerts, error banners.
    public static let card: CGFloat = 12
    /// 16 — modals, menus, empty-state puck, FilterChip.
    public static let panel: CGFloat = 16
    /// 24 — auth card, hero panels.
    public static let sheet: CGFloat = 24
}

public extension EdgeInsets {
    init(_ insets: UIEdgeInsets) {
        self.init(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }
}

public extension EdgeInsets {
    static let rowInsets: EdgeInsets = .init(
        top: 0,
        leading: ViewConst.screenPaddings,
        bottom: 0,
        trailing: ViewConst.screenPaddings
    )
}

/// The measured window safe area behind `ViewConst.safeAreaInsets`.
@MainActor @Observable
final class SafeAreaStore {
    static let shared = SafeAreaStore()
    /// Zero until the root's first layout — which happens under the splash.
    var insets = EdgeInsets()
}

public extension View {
    /// Measures the window's safe area for `ViewConst.safeAreaInsets`. Apply
    /// once, to the app's root view (it must not ignore the safe area).
    func measuresSafeArea() -> some View {
        background {
            // Ignores only the keyboard, so a raised keyboard never reads as
            // a taller bottom inset. The measurement must sit INSIDE the
            // ignore (it sees the safe area with the keyboard consumed);
            // measured outside it, the keyboard still counted — everything
            // placed from this inset (the mini player, docked composers)
            // rode up with the keyboard.
            Color.clear
                .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { insets in
                    if SafeAreaStore.shared.insets != insets { SafeAreaStore.shared.insets = insets }
                }
                .ignoresSafeArea(.keyboard)
        }
    }
}
