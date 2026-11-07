//
//  ProfileTracksTab.swift
//  Volspire
//
//  The artist's releases rail, then their tracks as one list, newest first.
//

import DesignSystem
import MediaLibrary
import SwiftUI

struct ProfileTracksTab: View {
    let viewModel: ProfileScreenViewModel
    let isOwnProfile: Bool

    @Environment(LibraryStore.self) private var libraryStore

    private var hasTracks: Bool { !viewModel.tracks.isEmpty }
    private var hasReleases: Bool {
        viewModel.profileUserId.map { !libraryStore.releases(for: $0).isEmpty } ?? false
    }
    private var releasesLoaded: Bool {
        viewModel.profileUserId.map { libraryStore.releasesLoaded(for: $0) } ?? true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section titles only when BOTH are here — with just one, the
            // tab already says what it is.
            if let userId = viewModel.profileUserId {
                ProfileReleasesRail(userId: userId, showsTitle: hasTracks)
            }
            if hasTracks && hasReleases {
                ProfileSectionTitle("Tracks")
                    .padding(.bottom, 8)
            }
            trackList
        }
    }

    @ViewBuilder
    private var trackList: some View {
        if !hasTracks {
            // Releases-only profiles show just the rail; the empty state is
            // for when there's nothing at all (once releases have answered).
            if releasesLoaded && !hasReleases {
                ProfileEmptyState(icon: ProfileTab.tracks.icon, title: "No tracks yet")
            }
        } else {
            LazyVStack(spacing: 4) {
                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { i, track in
                    ProfileMediaRow(
                        viewModel: viewModel,
                        id: track.id,
                        title: track.title,
                        subtitle: "@\(viewModel.username)",
                        coverURL: track.coverURL,
                        hidden: isOwnProfile ? track.visibility : nil
                    ) {
                        HStack(spacing: 6) {
                            streamsTrailing(track.streams)
                            if isOwnProfile { trackOptionsButton(track) }
                        }
                    }
                    .onTapGesture { viewModel.play(track) }
                    .staggeredAppear(i, in: "profile.tracks-\(ObjectIdentifier(viewModel).hashValue)")
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings - 6)
        }
    }

    /// Opens the Delete/Hide/Edit options sheet for an owned track.
    private func trackOptionsButton(_ track: ProfileTrack) -> some View {
        Button {
            viewModel.trackOptionsTrack = track
        } label: {
            LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                .foregroundStyle(Color.vText3)
                .frame(width: 32, height: 32)
                .minimumHitArea(for: 32)
        }
        .buttonStyle(.plain)
    }

    /// Trailing play-count for a track row (e.g. "▶ 1.2K").
    private func streamsTrailing(_ streams: Int) -> some View {
        HStack(spacing: 4) {
            LucideIcon(.playFill, .xs)
            Text(streams.compactCount)
        }
        .font(.appCaption)
        // A step up from the tertiary grey so the count reads.
        .foregroundStyle(Color.vText2)
        .monospacedDigit()
    }
}
