//
//  ProfileTracksTab.swift
//  Volspire
//
//  The artist's tracks as one list, newest first.
//

import DesignSystem
import MediaLibrary
import SwiftUI

struct ProfileTracksTab: View {
    let viewModel: ProfileScreenViewModel
    let isOwnProfile: Bool

    var body: some View {
        if viewModel.tracks.isEmpty {
            ProfileEmptyState(icon: .music, title: "No tracks yet")
        } else {
            LazyVStack(spacing: 4) {
                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { i, track in
                    ProfileMediaRow(
                        viewModel: viewModel,
                        id: track.id,
                        title: track.title,
                        subtitle: "@\(viewModel.username)",
                        coverURL: track.coverURL,
                        lock: isOwnProfile && track.isPrivate
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
                .contentShape(.rect)
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
        .foregroundStyle(Color.vText3)
        .monospacedDigit()
    }
}
