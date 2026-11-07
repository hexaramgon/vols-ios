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
    public static let timingIndicator: Font = .appLabel                // 13, semibold
    public static let button: Font = .appBodyLargeSemibold             // 17, semibold
    public static let mediaListHeaderSubtitle: Font = .appTitle2Regular // 20
    public static let mediaListItemSubtitle: Font = .appFootnote       // 13
    public static let mediaListItemFooter: Font = .appCalloutRegular   // 15

    /// THE list-row label pair — every track / playlist / person row's title +
    /// its second line (Library, profile, release & playlist pages, Explore
    /// rails, Search, Suggested, Add-to sheets). Change the size HERE.
    /// Exception: folder file rows, Analytics tracks and Followers &
    /// collaborators use `fileTitle` / `fileSubtitle` below. Title in white,
    /// subtitle in the tertiary grey. Change the size HERE — never pick
    /// per-screen fonts for a row.
    public static let trackTitle: Font = .appCallout                   // 15, medium
    public static let trackSubtitle: Font = .appSubheadline            // 14

    /// The compact row pair — Workspace folder file rows, and the rows that
    /// match them (Analytics tracks, Followers & collaborators, Blocked accounts). Title in
    /// `vTextRow`, subtitle in `vText3`. Change the size HERE.
    public static let fileTitle: Font = .appSubheadlineMedium          // 14, medium
    public static let fileSubtitle: Font = .appCaption                 // 13

    /// THE cover-card pair — the name + caption under a big cover tile in
    /// the browse views (Marketplace pack cards, playlist cards, profile
    /// release covers). Change the size HERE. (Rows use trackTitle/Subtitle.)
    /// Same weight as the track rows' title (`trackTitle`, medium), at 14.
    public static let cardTitle: Font = .appSubheadlineMedium         // 14, medium
    public static let cardSubtitle: Font = .appSubheadline             // 14

    /// Section headers — exactly two levels app-wide. `sectionTitle` is the
    /// big rail/page header ("Popular", "Playlists"); `sectionLabel` is the
    /// small group label above list groups (search results, notification day
    /// groups) in the tertiary text grey. No uppercase eyebrows — sentence-case
    /// text, no `.textCase(.uppercase)` / tracking (matches the web revamp).
    public static let sectionTitle: Font = .appTitle3                  // 18, semibold
    public static let sectionLabel: Font = .appLabel                   // 13, semibold
}

public extension Font {
    static var appFont: AppFont.Type {
        AppFont.self
    }
}
