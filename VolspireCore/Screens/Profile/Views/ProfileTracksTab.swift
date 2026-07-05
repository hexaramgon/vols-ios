//
//  ProfileTracksTab.swift
//  Volspire
//
//  "Recently Released" featured card + the rest of the artist's tracks.
//

import DesignSystem
import MediaLibrary
import SwiftUI

struct ProfileTracksTab: View {
    let viewModel: ProfileScreenViewModel
    let isOwnProfile: Bool

    var body: some View {
        if viewModel.tracks.isEmpty {
            ProfileEmptyState(
                icon: .music,
                title: "No tracks uploaded yet",
                subtitle: isOwnProfile ? "Your uploads will show up here." : nil
            )
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if let latest = viewModel.latestRelease {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Recently Released")
                        latestReleaseCard(latest)
                    }
                    .padding(.horizontal, ViewConst.screenPaddings)
                }

                if !viewModel.curatedTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("All Tracks")
                            .padding(.horizontal, ViewConst.screenPaddings)
                        LazyVStack(spacing: 4) {
                            ForEach(viewModel.curatedTracks) { track in
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
                            }
                        }
                        .padding(.horizontal, ViewConst.screenPaddings - 6)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.appBodyLargeBold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prominent "latest drop" card featuring the most recent track.
    private func latestReleaseCard(_ track: ProfileTrack) -> some View {
        let isActive = viewModel.mediaActivity(MediaID(track.id)) != nil
        return HStack(spacing: 14) {
            ArtworkView(track.coverURL.map { .webImage($0) } ?? .placeholder(name: track.title), cornerRadius: 10)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.appHeadline).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 9))
                    Text("\(track.streams.formatted()) streams").font(.appFootnote)
                }
                .foregroundStyle(Color.vText3)
            }
            Spacer(minLength: 8)
            if isOwnProfile { trackOptionsButton(track) }
            if isActive {
                ProfileEqualizerBars().padding(.trailing, 4)
            } else {
                ZStack {
                    Circle().fill(.white.opacity(0.12)).frame(width: 34, height: 34)
                    LucideIcon(.playFill, .sm).foregroundStyle(.white)
                }
            }
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(.rect)
        .onTapGesture { viewModel.play(track) }
    }

    /// Opens the Delete/Hide/Edit options sheet for an owned track.
    private func trackOptionsButton(_ track: ProfileTrack) -> some View {
        Button {
            viewModel.trackOptionsTrack = track
        } label: {
            LucideIcon(.ellipsis, .xl)
                .foregroundStyle(Color.vText3)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Trailing play-count for a track row (e.g. "▶ 1.2K").
    private func streamsTrailing(_ streams: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill").font(.system(size: 8))
            Text(streams.profileCompact)
        }
        .font(.appCaption)
        .foregroundStyle(Color.vText3)
        .monospacedDigit()
    }
}
