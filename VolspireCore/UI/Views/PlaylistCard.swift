//
//  PlaylistCard.swift
//  Volspire
//
//  The playlist cover card (cover + title + track count) shared by the Library
//  rail (fixed 158pt) and the Playlists grid (flexible column width) — the two
//  had identical copies, down to their press styles and skeletons.
//

import DesignSystem
import Services
import SwiftUI

struct PlaylistCard: View {
    let playlist: ApiPlaylist
    /// Resolved cover URL (bare storage paths must be resolved by the caller).
    let coverURL: URL?
    /// Fixed width (the Library rail's 158pt); nil fills a grid column with a
    /// square cover.
    var width: CGFloat? = nil
    let action: () -> Void

    private var artwork: Artwork {
        .placeholder(coverURL, name: playlist.title)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                cover

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title).font(.appFont.trackTitle).foregroundStyle(.white).lineLimit(1)
                    Text("\(playlist.trackCount ?? 0) tracks").font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width)
            .contentShape(.rect)
        }
        .buttonStyle(CardPress())
    }

    @ViewBuilder
    private var cover: some View {
        if let width {
            ArtworkView(artwork, cornerRadius: 16)
                .frame(width: width, height: width)
        } else {
            ArtworkView(artwork, cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The matching loading bones. Shimmer is applied by the enclosing skeleton
/// (both screens sweep one shimmer across their whole rail/grid).
struct PlaylistCardSkeleton: View {
    /// Fixed width (Library rail) or nil for a flexible square grid cell.
    var width: CGFloat? = nil
    var line2Width: CGFloat = 64

    private let bone = Color.white.opacity(0.06)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let width {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bone)
                    .frame(width: width, height: width)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bone)
                    .aspectRatio(1, contentMode: .fit)
            }
            Capsule().fill(bone).frame(width: 110, height: 12)
            Capsule().fill(bone).frame(width: line2Width, height: 10)
        }
        .frame(width: width, alignment: .leading)
    }
}
