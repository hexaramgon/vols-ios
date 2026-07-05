//
//  ProfileFeaturedTab.swift
//  Volspire
//
//  "Featured On" — tracks by other artists that credit this user, with the
//  credited role (and tombstones for tracks the owner privatised/delisted).
//

import DesignSystem
import SwiftUI

struct ProfileFeaturedTab: View {
    let viewModel: ProfileScreenViewModel

    var body: some View {
        if viewModel.creditedTracks.isEmpty {
            ProfileEmptyState(
                icon: .sparkles,
                title: "Nothing featured yet",
                subtitle: "Tracks by other artists that credit this profile show up here."
            )
        } else {
            list
        }
    }

    private var list: some View {
        LazyVStack(spacing: 4) {
            ForEach(viewModel.creditedTracks) { track in
                ProfileMediaRow(
                    viewModel: viewModel,
                    id: track.id,
                    title: track.title,
                    subtitle: "@\(track.artist)",
                    coverURL: track.coverURL,
                    dimmed: track.isUnavailable
                ) {
                    if track.isUnavailable {
                        Text(track.unavailableReason == "delisted" ? "Unavailable" : "Private")
                            .font(.appCaption).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    } else if !track.role.isEmpty {
                        Text(track.role).font(.appFootnote).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                }
                .opacity(track.isUnavailable ? 0.55 : 1)
                .onTapGesture { if !track.isUnavailable { viewModel.playCredited(track) } }
            }
        }
        .padding(.horizontal, 8)
    }
}
