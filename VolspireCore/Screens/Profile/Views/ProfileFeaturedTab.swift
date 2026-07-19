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
                        roleChip(track.unavailableReason == "delisted" ? "Unavailable" : "Private", dimmed: true)
                    } else if !track.role.isEmpty {
                        roleChip(track.role.capitalized)
                    }
                }
                .opacity(track.isUnavailable ? 0.55 : 1)
                .onTapGesture { if !track.isUnavailable { viewModel.playCredited(track) } }
            }
        }
        .padding(.horizontal, 8)
    }

    /// The credited role as a quiet chip — same scale as the category chips
    /// but neutral (roles are metadata, not a brand accent). Tombstones
    /// ("Private"/"Unavailable") share the shape, dimmed.
    private func roleChip(_ text: String, dimmed: Bool = false) -> some View {
        Text(text)
            .font(.appCaption2Semibold)
            .foregroundStyle(dimmed ? Color.vText3 : Color.vText2)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.07), in: Capsule())
    }
}
