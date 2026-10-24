//
//  NowPlayingBackground.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct NowPlayingBackground: View {
    let colors: [Color]
    /// 16 cover colours (4×4, row-major) → a mesh gradient; otherwise the
    /// two-colour linear wash.
    var meshColors: [Color] = []
    let expanded: Bool
    let isFullExpanded: Bool
    var canBeExpanded: Bool = true

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Rectangle()
            .fill(.thickMaterial)
            // The album wash rides in an overlay at full-screen height, top-
            // aligned: overlays never size their host, so the card (whatever
            // its height) just clips it. Sized to the shrinking card instead,
            // the collapse squashed the darkened bottom half up over
            // everything — a dark overlay flashing in on dismiss.
            .overlay(alignment: .top) {
                if canBeExpanded {
                    // Cheap static SwiftUI gradient / mesh: drawn once per
                    // track, no animation. Cross-fades to the new track's
                    // colours on switch (id + opacity transition).
                    ZStack {
                        Group {
                            if meshColors.count == 16 {
                                coverMesh
                            } else {
                                LinearGradient(
                                    colors: backgroundGradientColors,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                        }
                        .overlay(Color.black.opacity(0.2))
                        .id(meshColors.isEmpty ? colors : meshColors)
                        .transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.5), value: meshColors.isEmpty ? colors : meshColors)
                    .frame(height: UIScreen.size.height)
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

    /// The cover's 4×4 colours on an even grid, smoothly blended. A soft
    /// scrim toward the bottom keeps the transport legible over bright covers
    /// (the linear wash gets that from fading into the dark base).
    var coverMesh: some View {
        let stops: [Float] = [0, 1.0 / 3, 2.0 / 3, 1]
        let points = stops.flatMap { y in stops.map { x in SIMD2<Float>(x, y) } }
        return MeshGradient(width: 4, height: 4, points: points, colors: meshColors,
                            smoothsColors: true, colorSpace: .perceptual)
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
            )
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
