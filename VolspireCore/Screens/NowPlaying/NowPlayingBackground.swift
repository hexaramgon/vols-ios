//
//  NowPlayingBackground.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct NowPlayingBackground: View {
    let colors: [Color]
    let expanded: Bool
    let isFullExpanded: Bool
    var canBeExpanded: Bool = true

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thickMaterial)
            if canBeExpanded {
                // Cheap static SwiftUI gradient: album colours fading into the app's
                // dark base. The old version's cost was the *animated* Metal shader,
                // not the gradient — a LinearGradient rasterizes once, no per-frame work.
                // Cross-fades to the new track's colours on switch (id + opacity
                // transition, same pattern as the cover/title).
                ZStack {
                    LinearGradient(
                        colors: backgroundGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(Color.black.opacity(0.2))
                    .id(colors)
                    .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.5), value: colors)
                .opacity(expanded ? 1 : 0)
            }
        }
        .clipShape(.rect(cornerRadius: playerCornerRadius))
        .frame(height: expanded ? nil : ViewConst.compactNowPlayingHeight)
    }
}

private extension NowPlayingBackground {
    /// Album-tinted gradient stops fading into the app's dark base. Falls back to
    /// the brand wash (same feel as the Playlists / Workspace heroes) when no
    /// album colours are available — not a flat grey.
    var backgroundGradientColors: [Color] {
        let album = Array(colors.prefix(2))
        let base = Color(red: 1.0 / 255.0, green: 1.0 / 255.0, blue: 2.0 / 255.0)
        return album.isEmpty
            ? [Color.brand.opacity(0.42), Color.brand.opacity(0.12), base]
            : album + [base]
    }

    var playerCornerRadius: CGFloat {
        expanded ? expandPlayerCornerRadius : collapsedPlayerCornerRadius
    }

    var expandPlayerCornerRadius: CGFloat {
        isFullExpanded ? 0 : UIScreen.deviceCornerRadius
    }

    var collapsedPlayerCornerRadius: CGFloat {
        16
    }
}

#Preview {
    NowPlayingBackground(
        colors: [],
        expanded: false,
        isFullExpanded: false
    )
}
