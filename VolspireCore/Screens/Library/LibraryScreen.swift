//
//  LibraryScreen.swift
//  Volspire
//
//  The Library tab — the web's tablet/desktop-only music column brought to
//  the phone (formerly Explore's Music tab):
//  - Your playlists: a 2-column grid of cover cards (`GridCoverCard`, the
//    Workspace folders' look) — Saved tracks first, then every playlist;
//    tap opens, hold opens a playlist's options. New = the header bar's +.
//  - "Suggested for you": Tracks / Short tracks / Snippets (3 rows, "See all"
//    opens the full list as a playlist page) as numbered chart rows, on their
//    own tinted panel.
//

import DesignSystem
import MediaLibrary
import Services
import SharedUtilities
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
    /// The playlist being edited from its hold menu, and the form's draft.
    @State private var playlistToEdit: ApiPlaylist?
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var editCoverData: Data?
    @State private var editSaving = false
    /// "Suggested for you" hidden by the user (per device).
    @AppStorage("volspire:library:hide-suggestions") private var hideSuggestions = false


    var pad: CGFloat { ViewConst.screenPaddings }
    /// The page has scrolled under the header (shows its hairline).
    @State private var scrolled = false

    /// Bottom inset so the last rows clear the tab bar + the mini-player.
    var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("Library", scrolled: scrolled) {
                HeaderIconButton(icon: .plus, size: 36) { playlistsVM.showCreate = true }
                    .accessibilityLabel("New playlist")
            }
            .zIndex(1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        content
                    }
                    // Tight under the 44pt header bar (Settings' spacing).
                    .padding(.top, 4)
                    .padding(.bottom, bottomInset + 24)
                }
                .scrollIndicators(.hidden)
                .trackScrolledPastTop($scrolled)
                .refreshable { await refresh() }
                .onChange(of: router.rootResetTick) { _, _ in
                    // Re-tapping the Library tab: back to the top.
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
                    .init(icon: .squarePen, title: "Edit playlist") {
                        editTitle = p.title
                        editDescription = p.description ?? ""
                        editCoverData = nil
                        playlistToEdit = p
                    },
                    .init(
                        icon: .trash2, title: "Delete playlist", isDestructive: true,
                        confirm: DestructiveConfirm(
                            title: "Delete this playlist?",
                            message: "The tracks in it stay where they are."
                        ) { dependencies.contentActions.deletePlaylist(id: p.playlistId) }
                    ),
                ]
            )
            .sheetBackground()
        }
        // Hold menu → Edit: the playlist page's own edit sheet.
        // Same full-screen edit as the playlist page.
        .fullScreenCover(item: $playlistToEdit) { p in
            EditDetailsScreen(
                title: "Edit Playlist",
                subtitle: "Update cover, name, and details",
                cover: .init(data: $editCoverData, savedURL: libraryStore.playlistCover(p.coverUrl),
                             caption: "A square image, shown everywhere your playlist appears."),
                namePrompt: "Playlist name",
                name: $editTitle,
                description: $editDescription,
                hasChanges: editCoverData != nil
                    || editTitle.trimmingCharacters(in: .whitespacesAndNewlines) != p.title
                    || editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    != (p.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                busy: editSaving,
                onSave: { await saveEdit(p) }
            )
        }
    }

    private func saveEdit(_ playlist: ApiPlaylist) async {
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !editSaving else { return }
        editSaving = true
        defer { editSaving = false }
        do {
            try await libraryStore.editPlaylist(
                playlistId: playlist.playlistId,
                title: title,
                description: editDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                coverData: editCoverData
            )
            playlistToEdit = nil
        } catch {
            debugLog("[LibraryScreen] edit playlist: \(error)")
            ToastCenter.shared.show("Couldn't save the playlist. Try again.", style: .error)
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
            // never reads as part of your library. Only once your playlists
            // have landed — yours first, then the suggestions fade in below.
            if playlistsLoaded, suggestionsHidden {
                showSuggestionsRow
                    .padding(.top, 20)
                    .transition(.opacity)
            } else if playlistsLoaded {
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
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: playlistsLoaded)
        .animation(.easeOut(duration: 0.25), value: suggestionsHidden)
        // Skeleton → content crossfades (and any section that resizes glides)
        // instead of cutting; the rows themselves stagger in (staggeredAppear).
        .loadingCrossfade(loadKey)
    }

    /// Saved tracks + playlists have both answered (loaded or failed) — gates
    /// the suggestions, which never wait on a request that already gave up.
    private var playlistsLoaded: Bool {
        func settled(_ state: LoadState) -> Bool { state != .idle && state != .loading }
        return settled(libraryStore.loadState) && settled(libraryStore.playlistsLoadState)
    }

    /// Nothing saved and no playlists (once both have loaded).
    private var libraryEmpty: Bool {
        libraryStore.loadState == .loaded && libraryStore.playlistsLoadState == .loaded
            && libraryStore.savedTracks.isEmpty && libraryStore.playlists.isEmpty
    }

    /// An empty library always shows the suggestions — they're all there is
    /// to start from — whatever the hide preference says.
    private var suggestionsHidden: Bool { hideSuggestions && !libraryEmpty }

    /// Changes whenever a section's data lands.
    private var loadKey: [Bool] {
        [libraryStore.loadState == .loaded, libraryStore.playlistsLoadState == .loaded,
         feedStore.loadState == .loaded]
    }

    // MARK: Playlists

    /// "Your playlists": Saved tracks first, then each playlist, as grid
    /// cover cards (the Workspace folders' look) — every playlist, no Show
    /// all. Tap opens its page; hold opens a playlist's options.
    /// Bones until BOTH saved tracks and playlists respond (rendering Saved
    /// alone first made the grid grow under you on a cold start). "+ New"
    /// rides in the header; with nothing saved and no playlists, the ghost-
    /// rows empty state stands in for the whole section.
    @ViewBuilder
    private var playlistsSection: some View {
        let items = crateItems
        let loading = libraryStore.loadState != .loaded || libraryStore.playlistsLoadState != .loaded
        if libraryFailed && items.isEmpty {
            // Offline / load failure with nothing to show — never "empty".
            LoadErrorView(icon: .library, title: "Couldn't load your library") {
                Task { await refresh() }
            }
            .padding(.top, 40)
        } else if !loading && items.isEmpty {
            // Nothing saved, no playlists: the animated ghost-rows empty
            // state (My Network / Messages / Workspace).
            HomeEmpty(title: "Your library is empty", message: "Tracks you save and playlists you make live here.") {
                GhostListRows()
            } action: {
                PrimaryButton("New playlist", size: .inline, expands: false) { playlistsVM.showCreate = true }
            }
            .padding(.horizontal, pad)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Workspace's group heading, with "+ New" (populated sections
                // get the header pill — see empty-rail CTA pattern).
                // "New" is the header's + now.
                HStack(alignment: .center) {
                    Text("Your playlists")
                        .font(.appFont.sectionTitle)
                        .foregroundStyle(Color.vText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, pad).padding(.top, 12).padding(.bottom, 12)

                LazyVGrid(columns: playlistColumns, alignment: .leading, spacing: 20) {
                    if loading {
                        ForEach(0 ..< 4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Color.vSkeleton)
                                    .aspectRatio(1, contentMode: .fit)
                                Capsule().fill(Color.vSkeleton).frame(width: 110, height: 10)
                                Capsule().fill(Color.vSkeleton).frame(width: 70, height: 8)
                            }
                            .shimmering()
                        }
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            GridCoverCard(
                                title: item.title, caption: item.caption, optionsLabel: "Playlist options",
                                onLongPress: item.playlist.map { p in { playlistForOptions = p } },
                                action: item.open
                            ) {
                                CrateSleeve(item: item)
                            }
                            .staggeredAppear(i, in: "library.playlists")
                        }
                    }
                }
                .padding(.horizontal, pad)
            }
        }
    }

    /// Two square-art columns (Workspace's folder grid).
    private var playlistColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 2)
    }

    /// "12 tracks · 3 days ago" (last updated, else created).
    private func playlistCaption(tracks: Int?, date: String?) -> String? {
        var parts: [String] = []
        if let n = tracks { parts.append(n == 1 ? "1 track" : "\(n.compactCount) tracks") }
        if let date, !date.isEmpty { parts.append(MessageTime.agoLong(iso: date)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Saved tracks or playlists failed to load.
    private var libraryFailed: Bool {
        if case .error = libraryStore.loadState { return true }
        if case .error = libraryStore.playlistsLoadState { return true }
        return false
    }

    private var crateItems: [CrateItem] {
        var items: [CrateItem] = []
        let saved = savedMedia
        if !saved.isEmpty {
            let blurb = "Every track you've saved, all in one place."
            items.append(CrateItem(id: "saved", title: "Saved tracks",
                                   caption: playlistCaption(tracks: saved.count, date: nil), sleeve: .saved) {
                router.navigateToMedia(items: saved, listMeta: .init(artwork: nil, title: "Saved tracks", subtitle: blurb),
                                    showSave: false, compactHeader: true, savedTracks: true)
            })
        }
        for p in libraryStore.playlists {
            items.append(CrateItem(id: p.playlistId, title: p.title,
                                   caption: playlistCaption(tracks: p.trackCount, date: p.updatedAt ?? p.createdAt),
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
                    audioURL: StorageService().trackMediaURL(t.audioUrl)
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
            Spacer(minLength: 8)
            // Not dismissible while the library is empty (see suggestionsHidden).
            if !libraryEmpty {
                Button { hideSuggestions = true } label: {
                    LucideIcon(.x, .lg)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 36, height: 36)
                        .minimumHitArea(for: 36)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -8)
                .accessibilityLabel("Hide suggestions")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    /// Where the panel was, once hidden: one quiet row to bring it back.
    private var showSuggestionsRow: some View {
        Button { hideSuggestions = false } label: {
            HStack(spacing: 10) {
                LucideIcon(.sparkles, .sm)
                Text("Show Suggested for you")
                    .font(.appSubheadlineMedium)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.vText3)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
    /// "12 tracks · 3 days ago".
    var caption: String? = nil
    let sleeve: Sleeve
    /// The card's hold-for-options target — nil for Saved tracks (nothing to
    /// edit or delete).
    var playlist: ApiPlaylist? = nil
    let open: () -> Void
}

/// A crate item's art for its grid card: the Saved sleeve, the playlist's
/// cover, else its name mesh (no glyph, like folders and packs).
private struct CrateSleeve: View {
    let item: CrateItem

    var body: some View {
        switch item.sleeve {
        case .saved:
            SavedSleeve()
        case let .playlist(_, cover):
            if let cover {
                ArtworkView(.webImage(cover), cornerRadius: 0)
            } else {
                PlaylistCoverFallback(name: item.title, icon: nil)
            }
        }
    }
}
