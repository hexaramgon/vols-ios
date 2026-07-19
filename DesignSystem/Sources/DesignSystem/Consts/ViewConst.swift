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
    /// Header action-icon glyph size (bell / search / messages / "…"), used app-wide.
    static let headerIconSize: CGFloat = 24
    /// Back-chevron glyph size in pushed-screen nav bars. NB: the shared
    /// BackButton draws a Lucide chevron, whose inner viewBox padding makes it
    /// read ~25% smaller than an SF symbol at the same point size — this value
    /// is chosen for the Lucide rendering.
    static let backIconSize: CGFloat = 32
    static let compactNowPlayingHeight: CGFloat = 56

    static var safeAreaInsets: EdgeInsets {
        MainActor.assumeIsolated {
            EdgeInsets(UIApplication.keyWindow?.safeAreaInsets ?? .zero)
        }
    }
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
