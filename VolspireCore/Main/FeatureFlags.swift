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
}
