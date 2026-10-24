//
//  TrackListRow.swift
//  Volspire
//
//  The standard track list row (Library's saved list, Search's track results,
//  the collection "See all" screen): 50pt artwork with the playing-state
//  overlay, title + subtitle in the track type scale, then a trailing
//  @ViewBuilder accessory (save / "…" buttons). One home for the row anatomy —
//  three screens had copy-pasted it line for line.
//

import DesignSystem
import SwiftUI

struct TrackListRow<Accessory: View>: View {
    private let artwork: Artwork
    private let title: String
    private let subtitle: String?
    /// Playing/paused marker over the artwork (nil = not the active track).
    private let activity: MediaActivity?
    private let artworkSize: CGFloat
    /// Row-level horizontal padding, for lists whose container doesn't pad rows.
    private let horizontalPadding: CGFloat
    private let onTap: () -> Void
    private let accessory: Accessory

    init(
        artwork: Artwork,
        title: String,
        subtitle: String? = nil,
        activity: MediaActivity? = nil,
        artworkSize: CGFloat = 50,
        horizontalPadding: CGFloat = 0,
        onTap: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.artwork = artwork
        self.title = title
        self.subtitle = subtitle
        self.activity = activity
        self.artworkSize = artworkSize
        self.horizontalPadding = horizontalPadding
        self.onTap = onTap
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 13) {
            ArtworkView(artwork, cornerRadius: Radius.tile)
                .frame(width: artworkSize, height: artworkSize)
                .coverShadow()
                // Covers load/re-decode on their own schedule; without this a
                // container's entrance/loading animation catches that change and
                // slides the image in out of sync with its row. Clearing the
                // transaction animation lets it appear in place (the Library
                // entrance fix — a no-op for lists that don't animate).
                .transaction { $0.animation = nil }
                .overlay {
                    if let activity {
                        ZStack {
                            Color.vShade.opacity(0.45)
                            MediaActivityIndicator(state: activity).foregroundStyle(Color.vOnColor)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appFont.trackTitle)
                    // Row titles rest at `vTextRow`; the playing row lifts to full ink.
                    .foregroundStyle(activity != nil ? Color.vText : Color.vTextRow)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            accessory
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
    }
}

extension TrackListRow where Accessory == EmptyView {
    /// The accessory-less form (e.g. Search's track results).
    init(
        artwork: Artwork,
        title: String,
        subtitle: String? = nil,
        activity: MediaActivity? = nil,
        artworkSize: CGFloat = 50,
        horizontalPadding: CGFloat = 0,
        onTap: @escaping () -> Void
    ) {
        self.init(
            artwork: artwork,
            title: title,
            subtitle: subtitle,
            activity: activity,
            artworkSize: artworkSize,
            horizontalPadding: horizontalPadding,
            onTap: onTap
        ) {
            EmptyView()
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TrackListRow(
            artwork: .placeholder(name: "Demo"),
            title: "Midnight Drive",
            subtitle: "@wavelord",
            activity: .playing,
            onTap: {}
        ) {
            LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize).foregroundStyle(Color.vText3)
        }
        TrackListRow(
            artwork: .placeholder(name: "Demo"),
            title: "No accessory",
            subtitle: "@someone",
            onTap: {}
        )
    }
    .padding()
    .background(Color.vBase)
}
