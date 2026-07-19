//
//  AppFont.swift
//  Volspire
//
//

import SwiftUI

// Semantic aliases over the `Font.appXxx` type scale (Typography.swift) so each
// style has a single source of truth — these were exact `.geist(…)` duplicates
// of the tokens they now point at (values unchanged).
public enum AppFont {
    public static let timingIndicator: Font = .appLabel                // 12, semibold
    public static let button: Font = .appBodyLargeSemibold             // 17, semibold
    public static let mediaListHeaderSubtitle: Font = .appTitle2Regular // 20
    public static let mediaListItemSubtitle: Font = .appFootnote       // 13
    public static let mediaListItemFooter: Font = .appCalloutRegular   // 15

    /// The one media-label pair — EVERY track OR playlist title + its
    /// "@artist"/"N tracks" line in rows, cards and rails (home, library,
    /// search, playlists, profile, DMs, analytics, downloads) uses these two,
    /// title in white and the subtitle in the app's tertiary text grey.
    /// Don't pick per-screen fonts for media labels.
    public static let trackTitle: Font = .appCalloutSemibold           // 15, semibold
    public static let trackSubtitle: Font = .appFootnote               // 13

    /// Section headers — exactly two levels app-wide. `sectionTitle` is the
    /// big rail/page header ("Popular", "Playlists"); `sectionLabel` is the
    /// small ALL-CAPS group label above list groups (search results,
    /// notification day groups) — uppercase the text and pair it with
    /// `.tracking(0.6)` + the tertiary text grey at the site.
    public static let sectionTitle: Font = .appTitle3Bold              // 18, bold
    public static let sectionLabel: Font = .appLabel                   // 12, semibold
}

public extension Font {
    static var appFont: AppFont.Type {
        AppFont.self
    }
}
