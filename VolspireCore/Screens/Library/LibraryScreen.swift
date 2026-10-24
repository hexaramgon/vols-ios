//
//  LibraryScreen.swift
//  Volspire
//
//  The Library tab — the web's tablet/desktop-only music column brought to
//  the phone (formerly Explore's Music tab):
//  - Your playlists: Saved tracks first, then every playlist; each opens
//    its page. A "New playlist" row leads the list.
//  - "Suggested for you": Tracks / Short tracks / Snippets (3 rows, "See all"
//    opens the full list as a playlist page) as numbered chart rows, on their
//    own tinted panel.
//

import DesignSystem
import MediaLibrary
import Services
import SwiftUI

struct LibraryScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @Environment(PlayerController.self) var playerController
    @Environment(FeedStore.self) var feedStore
    @Environment(LibraryStore.self) var libraryStore

    @State var viewModel = LibraryScreenViewModel()
    @State private var playlistsVM = PlaylistsViewModel()
    /// The playlist whose "…" is open, and one picked for deletion.
    @State private var playlistForOptions: ApiPlaylist?
    @State private var playlistToDelete: ApiPlaylist?


    var pad: CGFloat { ViewConst.screenPaddings }

    /// Bottom inset so the last rows clear the tab bar + the mini-player.
    var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Library")
                .zIndex(1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        content
                    }
                    .padding(.top, 16)
                    .padding(.bottom, bottomInset + 24)
                }
                .scrollIndicators(.hidden)
                .refreshable { await refresh() }
                .onChange(of: router.rootResetTick) { _, _ in
                    withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.vBase.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            viewModel.player = dependencies.mediaPlayer
            playlistsVM.library = libraryStore
            async let saved: Void = libraryStore.loadIfNeeded()
            async let playlists: Void = libraryStore.loadPlaylistsIfNeeded()
            async let home: Void = feedStore.loadHomeIfNeeded()
            _ = await (saved, playlists, home)
        }
        .sheet(isPresented: $playlistsVM.showCreate) { PlaylistCreateSheet(viewModel: playlistsVM) }
        // A playlist row's "…" — the same sheet as a track's options.
        .sheet(item: $playlistForOptions) { p in
            TrackOptionsSheet(
                artwork: .placeholder(libraryStore.playlistCover(p.coverUrl), name: p.title),
                title: p.title,
                meta: p.trackCount.map { "\($0) track\($0 == 1 ? "" : "s")" },
                actions: [
                    .init(icon: .listMusic, title: "Open playlist") {
                        router.navigateToPlaylist(playlistId: p.playlistId, title: p.title)
                    },
                    .init(icon: .trash2, title: "Delete playlist", isDestructive: true) {
                        playlistToDelete = p
                    },
                ]
            )
            .sheetBackground()
        }
        .destructiveConfirm(
            "Delete this playlist?",
            isPresented: Binding(get: { playlistToDelete != nil }, set: { if !$0 { playlistToDelete = nil } })
        ) {
            guard let p = playlistToDelete else { return }
            Task { _ = await libraryStore.deletePlaylist(playlistId: p.playlistId) }
        }
    }

    private func refresh() async {
        async let feed: Void = feedStore.refreshAll()
        async let saved: Void = libraryStore.refresh()
        async let playlists: Void = libraryStore.refreshPlaylists()
        _ = await (feed, saved, playlists)
    }

    // MARK: Playback

    var currentTrackID: String? { playerController.state.currentMediaID?.value }
    var isPlaying: Bool { playerController.state.isPlaying }

    func isActive(_ track: HomeTrack) -> Bool { track.id == currentTrackID }

    /// Start the track (queueing its list), or toggle if it's already loaded.
    func handleTap(_ track: HomeTrack, in queue: [HomeTrack]) {
        if isActive(track) {
            playerController.onPlayPause()
        } else {
            Task { await viewModel.playTrack(track, in: queue) }
        }
    }
}

extension LibraryScreen {
    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Yours: playlists + saved tracks.
            playlistsSection

            // Not yours: everything below is Volspire's suggestions, set on
            // its own tinted panel under one "Suggested for you" header so it
            // never reads as part of your library.
            VStack(alignment: .leading, spacing: 0) {
                suggestionsHeader
                // Full-length songs (3 min+) — the same bucket as Explore's
                // Popular Today, so no extra request.
                shortList("Tracks", tracks: feedStore.popularTracks)
                shortList("Short tracks", tracks: feedStore.demos)
                shortList("Snippets", tracks: feedStore.samples, isLast: true)
            }
            .padding(.bottom, 12)
            .background(
                Color.vCard,
                in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
            )
            .padding(.top, 20)
        }
        // Skeleton → content crossfades (and any section that resizes glides)
        // instead of cutting; the rows themselves stagger in (staggeredAppear).
        .loadingCrossfade(loadKey)
    }

    /// Changes whenever a section's data lands.
    private var loadKey: [Bool] {
        [libraryStore.loadState == .loaded, libraryStore.playlistsLoadState == .loaded,
         feedStore.loadState == .loaded]
    }

    // MARK: Playlists

    /// The web's "Your playlists": Saved tracks first, then each playlist, as
    /// profile-style rows (44pt sleeve, name, chevron) — every playlist, no
    /// Show all. Each opens its own page.
    /// Bones until BOTH saved tracks and playlists respond (rendering Saved
    /// alone first made the list grow under you on a cold start). Always shown:
    /// the "New playlist" row leads it.
    @ViewBuilder
    private var playlistsSection: some View {
        let items = crateItems
        let loading = libraryStore.loadState != .loaded || libraryStore.playlistsLoadState != .loaded
        // Always shown — the New playlist row lives here.
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your playlists").font(.appFont.sectionTitle).foregroundStyle(Color.vText)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)

            // Profile-tab row geometry: rows 4pt apart, inset so each
            // row's own 6pt lead lands on the 16pt page column.
            if loading {
                SkeletonRows(count: 3, thumb: .rounded(size: 44, radius: 8),
                             thumbSpacing: 14, rowSpacing: 4,
                             horizontalPadding: 6, verticalPadding: 10)
                    .padding(.horizontal, ViewConst.screenPaddings - 6)
            } else {
                VStack(spacing: 4) {
                    NewPlaylistRow { playlistsVM.showCreate = true }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        CrateRow(item: item, onMore: item.playlist == nil ? nil : { playlistForOptions = item.playlist })
                            .staggeredAppear(i, in: "library.playlists")
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings - 6)
            }
        }
    }

    private var crateItems: [CrateItem] {
        var items: [CrateItem] = []
        let saved = savedMedia
        if !saved.isEmpty {
            let blurb = "Every track you've saved, all in one place."
            items.append(CrateItem(id: "saved", title: "Saved tracks", subtitle: blurb, sleeve: .saved) {
                router.navigateToMedia(items: saved, listMeta: .init(artwork: nil, title: "Saved tracks", subtitle: blurb),
                                    showSave: false, compactHeader: true, savedTracks: true)
            })
        }
        for p in libraryStore.playlists {
            let desc = p.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            items.append(CrateItem(id: p.playlistId, title: p.title,
                                   subtitle: desc.isEmpty ? nil : desc,
                                   sleeve: .playlist(id: p.playlistId, cover: libraryStore.playlistCover(p.coverUrl)),
                                   playlist: p) {
                router.navigateToPlaylist(playlistId: p.playlistId, title: p.title)
            })
        }
        return items
    }

    /// Saved tracks as playable media for the Saved tracks page.
    private var savedMedia: [Media] {
        libraryStore.savedTracks.map { t in
            Media(
                id: MediaID(t.trackId),
                meta: MediaMeta(
                    artwork: libraryStore.coverURL(for: t),
                    title: t.title,
                    artist: t.artist?.username,
                    audioURL: StorageService().resolveTrackUrl(t.audioUrl).flatMap { URL(string: $0) }
                )
            )
        }
    }

    // MARK: Suggestions

    /// Heads the suggestions panel: what this is, and that none of it is
    /// saved yet.
    private var suggestionsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            LucideIcon(.sparkles, .md)
                .foregroundStyle(Color.vText)
                .frame(width: 36, height: 36)
                .background(Color.vControl, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested for you")
                    .font(.appFont.sectionTitle)
                    .foregroundStyle(Color.vText)
                Text("New on Volspire · not in your library yet")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: Short lists

    @ViewBuilder
    private func shortList(_ title: String, tracks: [HomeTrack], isLast: Bool = false) -> some View {
        // Bones in the section's final shape until the home buckets respond,
        // so Short tracks / Snippets don't pop in and shift the page.
        if feedStore.loadState != .loaded {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.appHeadline).foregroundStyle(Color.vText2)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                ChartRowsSkeleton(count: 3)
            }
            .padding(.bottom, 8)
            // One divider between sections, none under the panel's last one.
            .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1).opacity(isLast ? 0 : 1) }
        } else if !tracks.isEmpty {
            let rows = Array(tracks.prefix(3))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title).font(.appHeadline).foregroundStyle(Color.vText2)
                    Spacer()
                    if tracks.count > 3 {
                        seeAllLink { openList(title, tracks: tracks) }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                    ChartRow(track: t, index: i, isActive: isActive(t), isPlaying: isPlaying) { handleTap(t, in: tracks) }
                        .staggeredAppear(i, in: "library.\(title)")
                }
            }
            .padding(.bottom, 8)
            // One divider between sections, none under the panel's last one.
            .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1).opacity(isLast ? 0 : 1) }
        }
    }
}

extension LibraryScreen {
    /// "See all ›" — opens the whole list as a playlist page.
    fileprivate func seeAllLink(_ action: @escaping () -> Void) -> some View {
        PillLinkButton(title: "See all", action: action)
    }

    /// The full suggestion list on the playlist-style collection page.
    fileprivate func openList(_ title: String, tracks: [HomeTrack]) {
        let items = tracks.map { t in
            Media(id: MediaID(t.id),
                  meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL))
        }
        router.navigateToMedia(items: items, listMeta: .init(artwork: nil, title: title, subtitle: listBlurb(title)),
                               showSave: false, compactHeader: true)
    }

    /// The short description under each suggestion page's title.
    private func listBlurb(_ title: String) -> String? {
        switch title {
        case "Tracks": "Full-length songs from artists on Volspire."
        case "Short tracks": "Quick listens, demos and shorter cuts."
        case "Snippets": "Bite-size clips and samples to dig through."
        default: nil
        }
    }
}

// MARK: - Crate rows

struct CrateItem: Identifiable {
    enum Sleeve {
        case saved
        case playlist(id: String, cover: URL?)
    }

    let id: String
    let title: String
    /// The playlist's own description, if it has one.
    var subtitle: String? = nil
    let sleeve: Sleeve
    /// The row's "…" — nil for Saved tracks (nothing to edit or delete).
    var playlist: ApiPlaylist? = nil
    let open: () -> Void
}

/// "New playlist" — the first row of Your playlists, in CrateRow's shape,
/// with a plus tile where the sleeve goes.
private struct NewPlaylistRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Quiet tile with a full-ink plus; the label carries the contrast.
                LucideIcon(.plus, .lg)
                    .foregroundStyle(Color.vText)
                    .frame(width: 44, height: 44)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("New playlist")
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(Color.vText)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One playlist (or Saved tracks) as a row in the profile Tracks-tab shape:
/// 44pt sleeve, the name, and — for playlists — the same "…" as a track row.
private struct CrateRow: View {
    let item: CrateItem
    var onMore: (() -> Void)? = nil

    var body: some View {
        Button(action: item.open) {
            HStack(spacing: 14) {
                sleeve
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // The name, with the playlist's description under it when it
                // has one (Saved tracks / undescribed playlists: name only).
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let onMore {
                    Button(action: onMore) {
                        LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                            .foregroundStyle(Color.vText3)
                            .frame(width: 34, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Playlist options")
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            // Same row height with or without the 44pt "…" target.
            .padding(.vertical, onMore == nil ? 10 : 8)
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    @ViewBuilder
    private var sleeve: some View {
        switch item.sleeve {
        case .saved:
            SavedSleeve()
        case let .playlist(_, cover):
            if let cover {
                ArtworkView(.webImage(cover), cornerRadius: 0)
            } else {
                PlaylistCoverFallback(name: item.title, iconSize: .md)
            }
        }
    }
}
