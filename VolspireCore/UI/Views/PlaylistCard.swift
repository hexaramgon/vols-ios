//
//  PlaylistCard.swift
//  Volspire
//
//  The playlist cover card shared by the Library grid and the Playlists
//  screen — the web's PlaylistCard: cover flush to the top of a soft panel,
//  title inside it underneath, and a "Private" badge on the cover (the only
//  state worth marking). No track count (removed at the user's request).
//

import DesignSystem
import Services
import SwiftUI

struct PlaylistCard: View {
    let playlist: ApiPlaylist
    /// Resolved cover URL (bare storage paths must be resolved by the caller).
    let coverURL: URL?
    /// Fixed width; nil fills a grid column with a square cover.
    var width: CGFloat? = nil
    let action: () -> Void

    private var isPrivate: Bool { playlist.visibility == "private" }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                Text(playlist.title)
                    .font(.appFont.cardTitle)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(width: width, alignment: .leading)
            .background(Color.vCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(CardPress())
        .accessibilityLabel(isPrivate ? "\(playlist.title), private" : playlist.title)
    }

    private var cover: some View {
        Color.vSurface
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let coverURL {
                    ArtworkView(.webImage(coverURL), cornerRadius: 0)
                } else {
                    PlaylistCoverFallback(name: playlist.title)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                if isPrivate { PrivateBadge().padding(8) }
            }
    }
}

/// Cover-less playlists: a 3×3 mesh gradient derived ONLY from the playlist
/// name, so the same name gives the same cover on every device and platform.
///
/// Spec (replicate exactly on web / Android):
///  1. key = name trimmed of whitespace, lowercased; bytes = UTF-8.
///  2. seed = FNV-1a 32-bit over the bytes (offset 2166136261, prime 16777619).
///  3. Random stream: xorshift32 — x ^= x << 13; x ^= x >> 17; x ^= x << 5
///     (all mod 2^32), starting from x = seed (0 → 1). `next()` advances and
///     returns x.
///  4. base hue = seed % 360.
///  5. 9 colours, row-major from the top-left; for each, three next() calls:
///     hue = (base + (r1 % 81) − 40) mod 360, sat = 0.55 + (r2 % 21) / 100,
///     light = 0.20 + (r3 % 26) / 100  → HSL.
///  6. Points: the even 3×3 grid (0, 0.5, 1), except the centre, which moves
///     by ((r % 31) − 15) / 100 on x then y (two more next() calls).
///  The list glyph sits on top at 64% white — or, for Volspire's own lists
///  (`volspireMark`), the white spear mark at 42% of the cover's width.
struct PlaylistCoverFallback: View {
    let name: String
    var iconSize: IconSize = .xl
    var volspireMark = false
    /// The glyph on the mesh (services use their own; nil = bare mesh).
    var icon: LucideIcon.Name? = .listMusic

    var body: some View {
        let mesh = Self.mesh(for: name)
        return MeshGradient(width: 3, height: 3, points: mesh.points, colors: mesh.colors)
            .overlay {
                if volspireMark {
                    GeometryReader { geo in
                        VolspireAppMark(size: min(geo.size.width, geo.size.height) * 0.42, color: .white)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                } else if let icon {
                    LucideIcon(icon, iconSize).foregroundStyle(Color.vOnColor.opacity(0.64))
                }
            }
    }

    /// Step 2 of the spec: FNV-1a 32-bit over the normalised name.
    nonisolated static func seed(for name: String) -> UInt32 {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seed: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            seed ^= UInt32(byte)
            seed = seed &* 16_777_619
        }
        return seed
    }

    /// Step 4: the mesh's base hue (also tints a folder's hero wash).
    nonisolated static func baseHue(for name: String) -> Int { Int(seed(for: name) % 360) }

    nonisolated static func mesh(for name: String) -> (points: [SIMD2<Float>], colors: [Color]) {
        let seed = seed(for: name)
        var x = seed == 0 ? 1 : seed
        func next() -> UInt32 {
            x ^= x << 13
            x ^= x >> 17
            x ^= x << 5
            return x
        }
        let base = Int(seed % 360)
        var colors: [Color] = []
        for _ in 0 ..< 9 {
            let hue = ((base + Int(next() % 81) - 40) % 360 + 360) % 360
            let sat = 0.55 + Double(next() % 21) / 100
            let light = 0.20 + Double(next() % 26) / 100
            colors.append(FolderPalette.hsl(hue, sat, light))
        }
        let dx = Float(Int(next() % 31) - 15) / 100
        let dy = Float(Int(next() % 31) - 15) / 100
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5 + dx, 0.5 + dy], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
        return (points, colors)
    }
}

/// Saved tracks' sleeve: always the same bundled blue gradient + a filled
/// bookmark, so it reads as "yours" rather than one more playlist.
struct SavedSleeve: View {
    var body: some View {
        // The bundled blue gradient, filled into whatever square the caller
        // sizes, with a filled bookmark scaled to ~40% of the side.
        Color.clear
            .overlay {
                Image("saved-tracks-background")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay {
                GeometryReader { geo in
                    LucideIcon(.bookmarkFill, size: min(geo.size.width, geo.size.height) * 0.38)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
    }
}

/// "🔒 Private" chip over artwork (the web's black/60 blurred badge).
struct PrivateBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            LucideIcon(.lock, .xs)
            Text("Private").font(.appMicroBold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

/// The matching loading bones. Shimmer is applied by the enclosing skeleton.
struct PlaylistCardSkeleton: View {
    var width: CGFloat? = nil
    var line2Width: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.vSkeleton.aspectRatio(1, contentMode: .fit)
            Capsule().fill(Color.vSkeleton).frame(width: 110, height: 12)
                .padding(.horizontal, 12)
                .padding(.vertical, 13)
        }
        .frame(width: width, alignment: .leading)
        .background(Color.vCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}

// MARK: - Grid cover card

/// The grid card shared by the Workspace folders and Library playlists (the
/// Marketplace pack card's anatomy): square art with the cover shadow, the
/// name over a quiet caption. Tap opens; press and hold opens the item's
/// options (no "…").
struct GridCoverCard<Art: View>: View {
    let title: String
    let caption: String?
    /// Accessibility name for the hold action ("Folder options").
    var optionsLabel = "Options"
    var onLongPress: (() -> Void)? = nil
    let action: () -> Void
    @ViewBuilder let art: () -> Art

    /// CardPress's press feedback, driven by the gestures below (a Button
    /// would also fire its tap when a long press is released).
    @State private var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Sized placeholder + art in its overlay (fill-images rule).
            Color.vSurface
                .aspectRatio(1, contentMode: .fit)
                .overlay { art() }
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .coverShadow()

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appFont.cardTitle)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.appFont.cardSubtitle)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .scaleEffect(pressed ? 0.97 : 1)
        .opacity(pressed ? 0.92 : 1)
        .animation(.easeOut(duration: 0.15), value: pressed)
        // Long press first, so a recognised hold cancels the tap.
        .onLongPressGesture(minimumDuration: 0.4) {
            guard let onLongPress else { return }
            Haptics.impact(.medium)
            onLongPress()
        } onPressingChanged: { pressed = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: optionsLabel) { onLongPress?() }
    }
}
