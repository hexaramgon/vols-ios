//
//  FeatureFlags.swift
//  Volspire
//
//  Central feature flags, mirroring the web app's `FEATURES` (lib/feature-flags.ts).
//  Flip a flag here to toggle a gated feature app-wide.
//

import Foundation

enum FeatureFlags {
    /// Monetization: paid track tiers, buyer downloads, and marketplace selling.
    /// Off until monetization ships — mirrors the web's `FEATURES.marketplace`
    /// (gated there on `NEXT_PUBLIC_FEATURE_MARKETPLACE`). When off, the upload
    /// flow hides Buyer Downloads, drops paid tiers, and uses free-only copy.
    static let marketplace = false

    /// Design preview of the Marketplace browse tab and its Sell entry points
    /// while monetization is still off: on in DEBUG builds only, so the design
    /// can be seen and iterated on from Xcode; Release / TestFlight never show
    /// it. Paid upload tiers and checkout stay behind `marketplace`.
    /// Parked (2026-10-23): the design is built; flip back to the DEBUG-only
    /// `true` below to see it again.
    // #if DEBUG
    // static let marketplacePreview = true
    // #else
    static let marketplacePreview = false
    // #endif

    /// Whether the full Marketplace (beats, services, paid packs) + its Sell
    /// entries show (live, or the preview).
    static var marketplaceSurfaces: Bool { marketplace || marketplacePreview }

    /// Free sample packs — the first slice of the marketplace, live ahead of
    /// monetization: the Marketplace tab showing free packs only, the pack
    /// page with a free download, "Pack" in New post (no price field), and
    /// free packs in search. Beats, services, prices and paid packs stay
    /// behind `marketplace`.
    static let freePacks = true

    /// The Marketplace tab shows (full marketplace, or free packs only).
    static var marketplaceTab: Bool { marketplaceSurfaces || freePacks }

    /// Only the free-packs slice is live: every marketplace surface shows
    /// free packs and nothing paid.
    static var freePacksOnly: Bool { freePacks && !marketplaceSurfaces }

    /// Experiment (2026-10-31): the Workspace tab shows folders as a 2-column
    /// grid of cover cards (the Marketplace pack card's anatomy) instead of
    /// the list rows. false = back to `WorkspaceFolderRow`.
    static let workspaceFolderGrid = true

    /// Native MilkDrop-style visualizer in the expanded player (full-bleed
    /// behind the controls via the sparkles button; quality toggle in
    /// Settings). Built as a POC — fully working, parked behind this flag.
    /// Flipping to true restores the whole feature: button, fullscreen layer,
    /// Settings row, and the audio tap.
    static let visualizer = false

    /// Profile banner photos. Parked (2026-10-24): off = every profile hero
    /// shows the username mesh, and the banner pickers in sign-up and Edit
    /// Profile are hidden. Stored banners stay in the database untouched —
    /// flip to true to bring the whole feature back. Mirrors the web's
    /// `FEATURES.profileBanners`.
    static let profileBanners = false
}

/// UserDefaults keys for user-configurable settings (shared between the
/// Settings screen and the features that read them).
enum SettingsKeys {
    /// Bool — visualizer renders at the battery-lean 1.25× profile instead of
    /// the crisp 2× default.
    static let visualizerLowPower = "visualizerLowPower"
    /// `DistanceUnit` raw value — how the Collab map's distances read.
    static let distanceUnit = "distanceUnit"
}

/// Settings → About → Distance. Defaults to the device's measurement system.
enum DistanceUnit: String, Hashable {
    case metric, imperial

    static var deviceDefault: DistanceUnit {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }
}
