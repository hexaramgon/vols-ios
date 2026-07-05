//
//  Typography.swift
//  DesignSystem
//
//  Global type hierarchy (Geist). Prefer these semantic styles over ad-hoc
//  `.geist(size:weight:)` calls so sizing stays consistent across the app.
//
//  Usage: `Text("Settings").font(.appLargeTitle)`
//

import SwiftUI

public extension Font {
    /// Large screen titles — "Settings", "Library".
    static let appLargeTitle = Font.geist(24, weight: .bold)
    /// Content section titles — "Recently Released" and screen sub-headers.
    static let appTitle = Font.geist(22, weight: .bold)
    /// Card / group titles.
    static let appTitle3 = Font.geist(18, weight: .semibold)
    /// Emphasised row titles and prominent labels.
    static let appHeadline = Font.geist(16, weight: .semibold)
    /// Standard body text.
    static let appBody = Font.geist(16)
    /// List-row titles — a slightly heavier body for scannability.
    static let appBodyMedium = Font.geist(16, weight: .medium)
    /// Buttons and compact controls.
    static let appCallout = Font.geist(15, weight: .medium)
    /// Secondary text.
    static let appSubheadline = Font.geist(14)
    /// Captions, row subtitles, helper text.
    static let appFootnote = Font.geist(13)
    /// Small captions / metadata.
    static let appCaption = Font.geist(12)
    /// Uppercase section labels — pair with `.tracking(0.6)` + `.textCase(.uppercase)`.
    static let appLabel = Font.geist(12, weight: .semibold)

    // MARK: Weight variants
    // Same sizes as above in the weights the app actually uses, so every call site
    // can drop its raw `.geist(size:weight:)` for a named token with no visual change.

    /// Bold card/group title (heavier `appTitle3`).
    static let appTitle3Bold = Font.geist(18, weight: .bold)
    /// Regular-weight 15pt — the plain sibling of `appCallout` (which is medium).
    static let appCalloutRegular = Font.geist(15)
    /// Emphasised 15pt — semibold callout (buttons, prominent chips).
    static let appCalloutSemibold = Font.geist(15, weight: .semibold)
    /// Medium 14pt secondary text.
    static let appSubheadlineMedium = Font.geist(14, weight: .medium)
    /// Semibold 14pt secondary text.
    static let appSubheadlineSemibold = Font.geist(14, weight: .semibold)
    /// Medium 13pt caption.
    static let appFootnoteMedium = Font.geist(13, weight: .medium)
    /// Semibold 13pt caption / small emphasis.
    static let appFootnoteSemibold = Font.geist(13, weight: .semibold)
    /// Medium 12pt metadata.
    static let appCaptionMedium = Font.geist(12, weight: .medium)
    /// Smallest text — 11pt badges, timestamps, dense metadata.
    static let appCaption2 = Font.geist(11)
    /// Medium 11pt.
    static let appCaption2Medium = Font.geist(11, weight: .medium)

    // MARK: Extended scale
    // Fills in the remaining sizes/weights the app uses so every call site can
    // drop its raw `.geist(size:weight:)` / `.system(size:)` for a named token.

    /// Oversized display — big stat numbers and splash headers (38pt).
    static let appDisplayLarge = Font.geist(38, weight: .bold)
    /// Display headers — hero/section stat numbers (34pt).
    static let appDisplay = Font.geist(34, weight: .bold)
    /// Sheet / feature titles (28pt).
    static let appTitleXXL = Font.geist(28, weight: .bold)
    /// Prominent screen titles above `appLargeTitle` (27pt).
    static let appTitleXL = Font.geist(27, weight: .bold)
    /// Semibold sibling of `appLargeTitle` (24pt).
    static let appLargeTitleSemibold = Font.geist(24, weight: .semibold)
    /// Semibold sibling of `appTitle` (22pt).
    static let appTitleSemibold = Font.geist(22, weight: .semibold)
    /// Section / sheet titles between `appTitle`(22) and `appTitle3`(18) — 20pt.
    static let appTitle2 = Font.geist(20, weight: .bold)
    /// Semibold 20pt title.
    static let appTitle2Semibold = Font.geist(20, weight: .semibold)
    /// Regular 20pt title.
    static let appTitle2Regular = Font.geist(20)
    /// Regular sibling of `appTitle3` (18pt).
    static let appTitle3Regular = Font.geist(18)
    /// Large body / prominent row titles (17pt).
    static let appBodyLarge = Font.geist(17)
    /// Medium 17pt.
    static let appBodyLargeMedium = Font.geist(17, weight: .medium)
    /// Semibold 17pt — sheet headers, prominent row titles.
    static let appBodyLargeSemibold = Font.geist(17, weight: .semibold)
    /// Bold 17pt.
    static let appBodyLargeBold = Font.geist(17, weight: .bold)
    /// Bold sibling of `appHeadline` (16pt).
    static let appHeadlineBold = Font.geist(16, weight: .bold)
    /// Bold sibling of `appCallout` (15pt).
    static let appCalloutBold = Font.geist(15, weight: .bold)
    /// Bold sibling of `appSubheadline` (14pt).
    static let appSubheadlineBold = Font.geist(14, weight: .bold)
    /// Bold sibling of `appFootnote` (13pt).
    static let appFootnoteBold = Font.geist(13, weight: .bold)
    /// Bold sibling of `appCaption` (12pt).
    static let appCaptionBold = Font.geist(12, weight: .bold)
    /// Semibold 11pt.
    static let appCaption2Semibold = Font.geist(11, weight: .semibold)
    /// Bold 11pt.
    static let appCaption2Bold = Font.geist(11, weight: .bold)
    /// Micro labels — tab bar, dense badges (10pt).
    static let appMicro = Font.geist(10)
    /// Medium 10pt.
    static let appMicroMedium = Font.geist(10, weight: .medium)
    /// Semibold 10pt.
    static let appMicroSemibold = Font.geist(10, weight: .semibold)
    /// Bold 10pt.
    static let appMicroBold = Font.geist(10, weight: .bold)
    /// Nano — the smallest badges (9pt).
    static let appNanoMedium = Font.geist(9, weight: .medium)
    /// Semibold 9pt.
    static let appNanoSemibold = Font.geist(9, weight: .semibold)
    /// Bold 9pt.
    static let appNanoBold = Font.geist(9, weight: .bold)
}
