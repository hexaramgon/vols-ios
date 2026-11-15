//
//  HomeScreen+Network.swift
//  Volspire
//
//  My Network — the feed from the people you follow, in the Workspace tab's
//  language: section titles over flat content, sideways rails, quiet cards.
//  The latest drop as one compact card, and "New releases" as profile-style rows
//  with a "…" menu. Playing anything queues the rest of the feed after it;
//  tapping a row plays but never pauses, the cover toggles.
//

import DesignSystem
import MediaLibrary
import Player
import Services
import SwiftUI

extension HomeScreen {
    var networkTab: some View {
        tabScroll(.network, horizontalPadding: 0, refresh: { await refreshTab(.network) }) {
            networkContent
                .loadingCrossfade(feedStore.followingLoaded)
        }
    }

    @ViewBuilder
    private var networkContent: some View {
        let feed = feedStore.followingTracks
        if !feedStore.followingLoaded && !feedStore.followingFailed {
            NetworkSkeleton()
        } else if feedStore.followingFailed && feed.isEmpty {
            LoadErrorView(icon: .userCheck, title: "Couldn't load your feed", message: "Check your connection and try again.") {
                Task { await viewModel.refreshFollowing() }
            }
            .padding(.top, 60)
        } else if feed.isEmpty {
            HomeEmpty(title: "Nothing here yet", message: "Follow some artists to see their releases in this feed.") {
                GhostReleaseCards()
            } action: {
                PrimaryButton("Find artists", size: .inline, expands: false) { selectTab(.collab) }
            }
            .padding(.horizontal, pad)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Latest drop").padding(.top, 24)
                LatestDropCard(track: feed[0], feed: feed, playback: playback,
                               onSelect: { select(feed[0], in: feed) },
                               onProfile: openArtist)
                    .padding(.horizontal, pad - 6)
                    .padding(.top, 12)
                    .staggeredAppear(0, in: "explore.network")

                if feed.count > 1 {
                    sectionTitle("New releases").padding(.top, 32)
                    LazyVStack(spacing: 4) {
                        ForEach(Array(feed.dropFirst().enumerated()), id: \.element.id) { i, t in
                            ReleaseRow(track: t, feed: feed, playback: playback,
                                       onSelect: { select(t, in: feed) },
                                       onProfile: openArtist)
                                .staggeredAppear(i + 1, in: "explore.network")
                                .onAppear {
                                    if t.id == feed.last?.id { Task { await feedStore.loadMoreFollowing() } }
                                }
                        }
                    }
                    .padding(.horizontal, pad - 6)
                    .padding(.top, 8)
                }

                if !feedStore.followingHasMore {
                    Text("You're all caught up.")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.appFont.sectionTitle)
            .foregroundStyle(Color.vText)
            .padding(.horizontal, pad)
    }

    private func openArtist(_ track: HomeTrack) {
        if let id = track.artistId { router.navigateToProfile(userId: id) }
    }
}

// MARK: - Latest drop

/// The newest release as one compact card (Workspace activity-card
/// language): cover; @artist, title, type (+ collab badge); a round Play in
/// the top-right corner with "…" under it.
private struct LatestDropCard: View {
    let track: HomeTrack
    let feed: [HomeTrack]
    let playback: HomePlayback
    let onSelect: () -> Void
    let onProfile: (HomeTrack) -> Void

    var body: some View {
        let playing = playback.showsPause(track)
        HStack(alignment: .top, spacing: 14) {
            Button { playback.toggle(track, feed) } label: {
                ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: Radius.tile)
                    .frame(width: 96, height: 96)
                    .coverShadow()
            }
            .buttonStyle(.plain)

            // Who + what (+ the collab badge) on the left; Play top-right with
            // "…" beneath it — the card is just the cover's height.
            VStack(alignment: .leading, spacing: 0) {
                Button { onProfile(track) } label: {
                    Text("@\(track.artist)")
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Text(track.title)
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)

                HStack(spacing: 6) {
                    Text(track.typeLabel)
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                    if track.lookingForCollab { CollabBadge() }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                playButton(playing: playing)
                Spacer(minLength: 4)
                ReleaseMenu(track: track, feed: feed, onProfile: onProfile)
            }
            .frame(height: 96)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentShape(.rect(cornerRadius: Radius.card))
        .onTapGesture(perform: onSelect)
    }

    /// Collab's Popular Today play: a round ink button, accent blue while
    /// it's the loaded track.
    private func playButton(playing: Bool) -> some View {
        let active = playback.isActive(track)
        return Button { playback.toggle(track, feed) } label: {
            LucideIcon(playing ? .pauseFill : .playFill, .md)
                .foregroundStyle(active ? Color.vOnColor : Color.vOnInverse)
                .frame(width: 40, height: 40)
                .background(active ? Color.vAccent : Color.vInverse, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: active)
        .accessibilityLabel(playing ? "Pause" : "Play")
    }
}

// MARK: - Release row

/// Profile Tracks-tab sizing: 44pt cover with the shadow, title over
/// "@artist · Track", EQ bars while it's the loaded track, then "…".
private struct ReleaseRow: View {
    let track: HomeTrack
    let feed: [HomeTrack]
    let playback: HomePlayback
    let onSelect: () -> Void
    let onProfile: (HomeTrack) -> Void

    var body: some View {
        let active = playback.isActive(track)
        HStack(spacing: 14) {
            Button { playback.toggle(track, feed) } label: {
                ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: 8)
                    .frame(width: 44, height: 44)
                    .playingCoverOverlay(active: active, playing: playback.isPlaying, cornerRadius: 8)
                    .coverShadow()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.appFont.trackTitle)
                    .foregroundStyle(active ? Color.vText : Color.vTextRow)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("@\(track.artist) · \(track.typeLabel)")
                        .lineLimit(1)
                    if track.lookingForCollab {
                        LucideIcon(.handshake, .xs)
                            .foregroundStyle(Color.vSuccessText)
                            .accessibilityLabel("Open to collab")
                    }
                }
                .font(.appFont.trackSubtitle)
                .foregroundStyle(Color.vText3)
            }
            Spacer(minLength: 8)
            ReleaseMenu(track: track, feed: feed, onProfile: onProfile)
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(active ? Color.vRowActive : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Shared bits

/// The release "…": the app's standard options sheet (same as a track's
/// "…" elsewhere) — Save / Comments / Add to playlist / Share / the artist.
/// Comments open the track in the expanded player.
private struct ReleaseMenu: View {
    let track: HomeTrack
    let feed: [HomeTrack]
    let onProfile: (HomeTrack) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var playerController
    @Environment(Dependencies.self) private var dependencies
    @State private var showOptions = false
    @State private var showAddToPlaylist = false

    var body: some View {
        Button { showOptions = true } label: {
            LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                .foregroundStyle(Color.vText2)
                .frame(width: 32, height: 32)
                .minimumHitArea(for: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More options")
        .sheet(isPresented: $showOptions) {
            TrackOptionsSheet(
                artwork: .placeholder(track.coverURL, name: track.title),
                title: track.title,
                artist: "@\(track.artist)",
                actions: actions,
                queueMedia: Media(id: MediaID(track.id), meta: MediaMeta(
                    artwork: track.coverURL, title: track.title, artist: track.artist,
                    artistId: track.artistId, audioURL: track.audioURL
                ))
            )
            .sheetBackground()
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: track.id)
        }
    }

    private var actions: [TrackOptionsSheet.Action] {
        let saved = library.isSaved(track.id)
        var list: [TrackOptionsSheet.Action] = [
            .init(icon: saved ? .bookmarkFill : .bookmark, title: saved ? "Saved" : "Save", dismissesSheet: false) {
                _ = await library.toggleSave(trackId: track.id)
            },
            .init(icon: .messageCircle, title: "Comments") { openComments() },
            .init(icon: .listPlus, title: "Add to playlist") { showAddToPlaylist = true },
            .init(icon: .share2, title: "Share") {
                ShareActions.shareTrack(title: track.title, trackId: track.id)
            },
        ]
        if track.artistId != nil {
            list.append(.init(icon: .user, title: "Go to @\(track.artist)") { onProfile(track) })
        }
        return list
    }

    private func openComments() {
        Task {
            if playerController.state.currentMediaID?.value != track.id {
                await dependencies.mediaPlayer.play(MediaID(track.id), queue: feed.map {
                    Media(id: MediaID($0.id), meta: MediaMeta(artwork: $0.coverURL, title: $0.title, artist: $0.artist, artistId: $0.artistId, audioURL: $0.audioURL))
                })
            }
            playerController.pendingExpand = true
        }
    }
}

/// Small emerald "Collab" tag for releases flagged open to collaboration.
private struct CollabBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            LucideIcon(.handshake, .xs)
            Text("Open to collab").font(.appCaptionMedium)
        }
        .foregroundStyle(Color.vSuccessText)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color.vSuccess.opacity(0.15), in: Capsule())
    }
}

// MARK: - Skeleton

/// The page's final shape: the drop card, then rows.
private struct NetworkSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 110, height: 18)
                .padding(.horizontal, ViewConst.screenPaddings)
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.vCardSolid)
                .frame(height: 124)
                .padding(.horizontal, ViewConst.screenPaddings - 6)
                .padding(.top, 12)

            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 130, height: 18)
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 32)
            SkeletonRows(count: 4, thumb: .rounded(size: 44, radius: 8),
                         line1: CGSize(width: 160, height: 12), line2: CGSize(width: 90, height: 10),
                         thumbSpacing: 14, rowSpacing: 4,
                         horizontalPadding: 6, verticalPadding: 10)
                .padding(.horizontal, ViewConst.screenPaddings - 6)
                .padding(.top, 8)
        }
        .shimmering()
    }
}
