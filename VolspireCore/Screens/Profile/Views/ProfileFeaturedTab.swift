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
        if viewModel.creditedTracks.isEmpty && !viewModel.creditedLoaded {
            SkeletonRows(count: 5, thumb: .rounded(size: 40), line2: nil)
        } else if viewModel.creditedTracks.isEmpty {
            ProfileEmptyState(icon: ProfileTab.featuredOn.icon, title: "Not featured yet")
        } else {
            list
        }
    }

    private var list: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(viewModel.creditedTracks.enumerated()), id: \.element.id) { i, track in
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
                .staggeredAppear(i, in: "profile.featured-\(ObjectIdentifier(viewModel).hashValue)")
            }
        }
        .padding(.horizontal, 8)
    }

    /// The credited role as the app's quiet capsule tag (the control fill,
    /// like the listing tags / secondary pills) — neutral, roles are metadata.
    /// Tombstones ("Private"/"Unavailable") share the shape, dimmed.
    private func roleChip(_ text: String, dimmed: Bool = false) -> some View {
        Text(text)
            .font(.appCaption2Semibold)
            .foregroundStyle(dimmed ? Color.vText3 : Color.vTextRow)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.vControl, in: Capsule())
    }
}
