//
//  FolderArt.swift
//  Volspire
//
//  A folder's "album art" (web `lib/folder-art.ts` + `folder-art.tsx`):
//  folders have no cover image, so each gets the same name-seeded 3×3 mesh
//  as a cover-less playlist (see `PlaylistCoverFallback` for the spec) — the
//  same folder name is the same art in the folder list, the overview, its
//  own hero and on every platform. Fixed colours (not themed): it's artwork.
//

import DesignSystem
import SwiftUI

enum FolderPalette {
    /// The hero backdrop: the folder's colour (the base hue of its name mesh)
    /// fading into the canvas.
    static func wash(name: String) -> LinearGradient {
        let h = PlaylistCoverFallback.baseHue(for: name)
        return LinearGradient(
            stops: [
                .init(color: hsl(h, 0.55, 0.32).opacity(0.55), location: 0),
                .init(color: hsl(h, 0.55, 0.20).opacity(0.18), location: 0.55),
                .init(color: hsl(h, 0.55, 0.20).opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// HSL → sRGB (h in degrees, s/l in 0…1).
    static func hsl(_ h: Int, _ s: Double, _ l: Double) -> Color {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = Double(h % 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch hp {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return Color(red: r + m, green: g + m, blue: b + m)
    }
}

/// The folder tile: its name-seeded colour mesh. Only the folder page's
/// hero shows the name's first letter on it (`showsLetter`).
struct FolderArt: View {
    enum Size {
        /// `row`: the 44pt tile of a track row's cover (radius 8), for lists
        /// that sit alongside tracks.
        /// `lgCompact`: the hero cover on narrow phones, so the actions
        /// still fit beside it.
        case xs, sm, row, md, lgCompact, lg
        var side: CGFloat {
            switch self {
            case .xs: 20
            case .sm: 40
            case .row: 44
            case .md: 56
            case .lgCompact: 88
            case .lg: 112
            }
        }
        var radius: CGFloat {
            switch self {
            case .xs, .sm: Radius.tile
            case .row: 8
            case .md: Radius.card
            case .lgCompact, .lg: Radius.panel
            }
        }
    }

    let id: String
    let name: String
    var size: Size = .sm
    var showsLetter = false

    var body: some View {
        let mesh = PlaylistCoverFallback.mesh(for: name)
        MeshGradient(width: 3, height: 3, points: mesh.points, colors: mesh.colors)
            .frame(width: size.side, height: size.side)
            .clipShape(RoundedRectangle(cornerRadius: size.radius, style: .continuous))
            .overlay {
                if showsLetter {
                    Text(letter)
                        .font(.appDisplayLarge)
                        // 48pt at lg, 38pt at lgCompact (the hero sizes).
                        .scaleEffect(size == .lg ? 1.26 : 1)
                        .foregroundStyle(Color.vOnColor.opacity(0.9))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
            }
            .shadow(color: .black.opacity(size == .xs ? 0 : 0.3), radius: 8, y: 4)
            .accessibilityHidden(true)
    }

    private var letter: String {
        (name.trimmingCharacters(in: .whitespaces).first).map { String($0).uppercased() } ?? "?"
    }
}
