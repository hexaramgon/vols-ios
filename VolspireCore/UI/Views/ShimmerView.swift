//
//  ShimmerView.swift
//  Volspire
//

import DesignSystem
import SwiftUI

/// Skeleton treatment used by loading placeholders across the app (profile,
/// messages, library, marketplace, workspace). Now an Airbnb-style shimmer
/// sweep, centralised on the shared DesignSystem `shimmering()` modifier so
/// every call site stays consistent — the name is kept for its existing sites.
extension View {
    func skeletonPulse() -> some View {
        shimmering()
    }
}
