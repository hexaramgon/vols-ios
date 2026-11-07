//
//  ProfileMediaRow.swift
//  Volspire
//
//  Library-style track row (artwork, title + subtitle, active-row highlight,
//  equaliser when playing) shared by the Tracks and Featured-On tabs.
//

import DesignSystem
import MediaLibrary
import SwiftUI

struct ProfileMediaRow<Trailing: View>: View {
    let viewModel: ProfileScreenViewModel
    let id: String
    let title: String
    let subtitle: String
    let coverURL: URL?
    var dimmed: Bool = false
    /// Owner's view of a track that isn't public — private gets the lock and
    /// "only you", unlisted the link glyph and "anyone with the link".
    var hidden: TrackVisibility? = nil
    let trailing: Trailing

    init(
        viewModel: ProfileScreenViewModel,
        id: String,
        title: String,
        subtitle: String,
        coverURL: URL?,
        dimmed: Bool = false,
        hidden: TrackVisibility? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.viewModel = viewModel
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.dimmed = dimmed
        self.hidden = hidden == .public ? nil : hidden
        self.trailing = trailing()
    }

    private var hiddenNote: String? {
        switch hidden {
        case .private: "Hidden · only you can see it"
        case .unlisted: "Unlisted · anyone with the link"
        default: nil
        }
    }

    var body: some View {
        let isActive = viewModel.mediaActivity(MediaID(id)) != nil
        HStack(spacing: 14) {
            ArtworkView(.placeholder(coverURL, name: title), cornerRadius: 8)
                .frame(width: 44, height: 44)
                .playingCoverOverlay(active: isActive,
                                     playing: viewModel.mediaActivity(MediaID(id)) == .playing,
                                     cornerRadius: 8)
                .coverShadow()
                .grayscale(dimmed ? 1 : 0)
                // Not-public track, owner's view: the cover fades back under
                // a lock (private) or link (unlisted) badge, so it reads as
                // "not public" at a glance.
                .opacity(hidden == nil ? 1 : 0.45)
                .overlay {
                    if let hidden {
                        LucideIcon(hidden.icon, .sm)
                            .foregroundStyle(Color.white)
                            .frame(width: 26, height: 26)
                            .background(Color.black.opacity(0.6), in: Circle())
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // Same type as the Home chart rows (`ChartRow`).
                    Text(title)
                        .font(.appFont.trackTitle)
                        .foregroundStyle(hidden == nil ? Color.vText : Color.vText2)
                        .lineLimit(1)
                }
                // Says it outright instead of a tiny badge by the title.
                Text(hiddenNote ?? subtitle)
                    .font(.appFont.trackSubtitle)
                    .foregroundStyle(Color.vText3)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(
            isActive ? Color.vRowActive : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(.rect)
    }
}
