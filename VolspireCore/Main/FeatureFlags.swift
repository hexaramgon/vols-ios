//
//  FeatureFlags.swift
//  Volspire
//
//  Central feature flags, mirroring the web app's `FEATURES` (lib/feature-flags.ts).
//  Flip a flag here to toggle a gated feature app-wide.
//

enum FeatureFlags {
    /// Monetization: paid track tiers, buyer downloads, and marketplace selling.
    /// Off until monetization ships — mirrors the web's `FEATURES.marketplace`
    /// (gated there on `NEXT_PUBLIC_FEATURE_MARKETPLACE`). When off, the upload
    /// flow hides Buyer Downloads, drops paid tiers, and uses free-only copy.
    static let marketplace = false

    /// Native MilkDrop-style visualizer in the expanded player (full-bleed
    /// behind the controls via the sparkles button; quality toggle in
    /// Settings). Built as a POC — fully working, parked behind this flag.
    /// Flipping to true restores the whole feature: button, fullscreen layer,
    /// Settings row, and the audio tap.
    static let visualizer = false
}

/// UserDefaults keys for user-configurable settings (shared between the
/// Settings screen and the features that read them).
enum SettingsKeys {
    /// Bool — visualizer renders at the battery-lean 1.25× profile instead of
    /// the crisp 2× default.
    static let visualizerLowPower = "visualizerLowPower"
}
