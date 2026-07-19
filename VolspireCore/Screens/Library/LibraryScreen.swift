 //
//  LibraryScreen.swift
//  Volspire
//
//  Your stuff in one place: a Playlists rail up top + your Saved tracks below.
//  Both are visible at a glance — no toggle — so each is always reachable.
//  (Workspace folders live on the Home tab's Workspace section, not here.)
//

import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

struct LibraryScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @Environment(PlayerController.self) private var playerController

    @State private var viewModel = LibraryScreenViewModel()
    @State private var playlistsVM = PlaylistsViewModel()
    @State private var selectedTrack: ApiUserLike? = nil
    @State private var addToPlaylistTrack: ApiUserLike? = nil
    /// Header reveal-search (same pattern as Messages/Marketplace): hidden by
    /// default, revealed + focused by the header search icon, filters inline.
    @State private var showSearchField = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    /// Flips true once all three sections' first load resolves — until then the
    /// whole page shows one skeleton, then the real content cascades in together
    /// (mirrors the Marketplace skeleton → grid pattern).
    @State private var didLoad = false
    @State private var contentAppeared = false

    /// Bottom inset so the last rows clear the tab bar + (when present) the
    /// mini-player docked above it — same formula as Search / Messages /
    /// MediaCollection so every scrolling tab bottoms out consistently.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    /// A saved-track row.
    fileprivate struct Row: Identifiable {
        let id: String
        let title: String
        let artist: String?
        let coverURL: URL?
    }

    private var rows: [Row] {
        viewModel.savedTracks.map {
            Row(id: $0.trackId, title: $0.title, artist: $0.artist?.username, coverURL: viewModel.coverURL(for: $0))
        }
    }

    /// True while the playlists rail should still show its skeleton.
    private var playlistsLoading: Bool {
        playlistsVM.isLoading && playlistsVM.playlists.isEmpty
    }

    /// The saved-tracks load got no response and nothing across the page is cached
    /// — show the shared offline state (same as Home / Marketplace).
    private var showLibraryError: Bool {
        viewModel.loadFailed
            && viewModel.savedTracks.isEmpty && viewModel.uploadedTracks.isEmpty
            && playlistsVM.playlists.isEmpty
    }

    /// Retry every section (mirrors the pull-to-refresh).
    private func reloadAll() {
        Task {
            async let a: () = viewModel.refresh(currentUserId: dependencies.authManager.currentUserId)
            async let b: () = playlistsVM.load()
            _ = await (a, b)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1) // keep the header (and its sliding search reveal) above the scrolling content
            ScrollView {
                Group {
                    if !didLoad {
                        librarySkeleton
                            .transition(.opacity)
                    } else if showLibraryError {
                        // Couldn't reach the server and nothing's cached to show.
                        LoadErrorView { reloadAll() }
                            .frame(minHeight: UIScreen.size.height * 0.6)
                            .transition(.opacity)
                    } else if isSearching {
                        // A query is typed — swap the sections for matching saved
                        // tracks (crossfade, same as the Messages inline filter).
                        searchResults
                            .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            // First section fades in place (anchored) while the rest
                            // cascade up — matches Profile's hero-then-cascade feel.
                            // Fade only (distance 0): these sections hold async cover
                            // images (ArtworkView), which render in their own layer and
                            // would sit at their final spot while the row slides up to
                            // meet them. A fade has no positional move, so nothing lags
                            // (same fix as the profile tabs).
                            playlistsSection.entranceReveal(contentAppeared, index: 0, distance: 0)
                            savedSection.entranceReveal(contentAppeared, index: 1, distance: 0)
                        }
                        .transition(.opacity)
                        .onAppear { contentAppeared = true }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, bottomInset)
                .animation(.easeInOut(duration: 0.35), value: didLoad)
                .animation(.easeInOut(duration: 0.35), value: showLibraryError)
                .animation(.easeInOut(duration: 0.2), value: isSearching)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                async let a: () = viewModel.refresh(currentUserId: dependencies.authManager.currentUserId)
                async let b: () = playlistsVM.load()
                _ = await (a, b)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSearchField)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationBarHidden(true)
        .gradientBackground()
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
            // Load both sections concurrently so they resolve together
            // instead of popping in one after another.
            async let a: () = viewModel.load(currentUserId: dependencies.authManager.currentUserId)
            async let b: () = playlistsVM.load()
            _ = await (a, b)
            didLoad = true
        }
        .sheet(item: $selectedTrack) { track in
            LibraryTrackSheet(
                track: track,
                viewModel: viewModel,
                router: router,
                onDismiss: { selectedTrack = nil },
                onAddToPlaylist: { addToPlaylistTrack = track }
            )
            // Detents come from TrackOptionsSheet itself (sized to its rows).
            .sheetBackground()
        }
        .sheet(item: $addToPlaylistTrack) { track in
            AddToPlaylistSheet(trackId: track.trackId)
                // Detents come from the sheet itself (.medium/.large so long
                // playlist lists can expand).
                .sheetBackground()
        }
        .sheet(isPresented: $playlistsVM.showCreate) { playlistCreateSheet }
    }
}

// MARK: - Header

private extension LibraryScreen {
    var header: some View {
        ScreenHeader("Library") {
            HeaderIconButton(icon: .search) {
                withAnimation(.easeInOut(duration: 0.2)) { showSearchField = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
            }
        } expansion: {
            // Inside the header chrome so the bar background sits behind the
            // field — not floating over the page content.
            if showSearchField {
                HeaderSearchField(
                    prompt: "Search saved tracks…",
                    text: $searchText,
                    isRevealed: $showSearchField,
                    focus: $searchFocused
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// A consistent, modern section header: a bold title with an optional
    /// "See all" action on the right.
    func sectionHead(_ title: String, seeAll: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center) {
            Text(title).font(.appFont.sectionTitle).foregroundStyle(.white)
            Spacer(minLength: 0)
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 2) {
                        Text("See all").font(.appFootnoteMedium)
                        LucideIcon(.chevronRight, .xs)
                    }
                    .foregroundStyle(.white)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
    }
}

// MARK: - Full-page skeleton

private extension LibraryScreen {
    /// Whole-page skeleton shown until every section's first load resolves, so all
    /// the real content reveals together (mirrors the Marketplace skeleton → grid).
    var librarySkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            skeletonSection(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) { ForEach(0 ..< 3, id: \.self) { _ in PlaylistCardSkeleton(width: 158) } }
                        .padding(.horizontal, ViewConst.screenPaddings)
                }
                .scrollDisabled(true)
            }
            skeletonSection(spacing: 10) {
                SkeletonRows(count: 6, shimmers: false)
            }
        }
        .shimmering()
    }

    /// A skeleton section: a title bone over its (rail/list) content.
    func skeletonSection<Content: View>(spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Capsule().fill(Color.white.opacity(0.06))
                .frame(width: 150, height: 20)
                .padding(.horizontal, ViewConst.screenPaddings)
            content()
        }
    }

}

// MARK: - Playlists section

private extension LibraryScreen {
    var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            playlistsHead

            if !playlistsLoading, playlistsVM.playlists.isEmpty {
                // Empty: a slim full-width card with a real CTA instead of a
                // rail-sized dashed tile.
                emptyPlaylistsRow
                    .transition(.opacity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        if playlistsLoading {
                            ForEach(0 ..< 2, id: \.self) { _ in PlaylistCardSkeleton(width: 158) }
                                .transition(.opacity)
                        } else {
                            ForEach(playlistsVM.playlists) { playlistCard($0) }
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .animation(.easeInOut(duration: 0.3), value: playlistsLoading)
                    // One shimmer sweep across the whole rail while loading, not per-card.
                    .shimmering(active: playlistsLoading)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playlistsLoading)
    }

    /// "Playlists" section head with the gradient "New" pill once playlists
    /// exist (the empty state has its own CTA row) — replaces the old dashed
    /// trailing tile in the rail — plus the usual "See all". Same pattern as
    /// the Home Workspace tab's Folders header.
    var playlistsHead: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Playlists").font(.appFont.sectionTitle).foregroundStyle(.white)
            Spacer(minLength: 0)
            if !playlistsVM.playlists.isEmpty {
                AccentPillButton(title: "New") { playlistsVM.showCreate = true }
                Button { router.navigateToPlaylists() } label: {
                    HStack(spacing: 2) {
                        Text("See all").font(.appFootnoteMedium)
                        LucideIcon(.chevronRight, .xs)
                    }
                    .foregroundStyle(.white)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
    }

    /// Compact empty state: one line of copy + a prominent Create button.
    var emptyPlaylistsRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("No playlists yet")
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(.white)
                Text("Collect tracks you love in one place.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }
            Spacer(minLength: 8)
            AccentPillButton(title: "Create") { playlistsVM.showCreate = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.vCard))
        .padding(.horizontal, ViewConst.screenPaddings)
    }

    func playlistCard(_ playlist: ApiPlaylist) -> some View {
        PlaylistCard(playlist: playlist, coverURL: playlistsVM.cover(playlist.coverUrl), width: 158) {
            router.navigateToPlaylist(playlistId: playlist.playlistId, title: playlist.title)
        }
    }

    var playlistCreateSheet: some View {
        PlaylistCreateSheet(viewModel: playlistsVM)
    }
}

// MARK: - Saved section (track list)

private extension LibraryScreen {
    var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHead("Recently Saved", seeAll: rows.isEmpty ? nil : { showAllSaved() })
            savedContent
                .animation(.easeInOut(duration: 0.3), value: viewModel.loadingState)
        }
    }

    @ViewBuilder
    var savedContent: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            SkeletonRows(count: 5)
                .transition(.opacity)
        case let .error(message):
            inlineState(icon: .triangleAlert, title: "Something went wrong", subtitle: message)
                .transition(.opacity)
        case .loaded where rows.isEmpty:
            inlineState(icon: .listMusic, title: "No saved tracks", subtitle: "Tracks you save will live here.")
                .transition(.opacity)
        case .loaded:
            let visible = Array(rows.prefix(viewModel.savedLimit))
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    trackRow(row, isLast: index == visible.count - 1)
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .transition(.opacity)
        }
    }

    func showAllSaved() {
        router.navigateToMedia(
            items: viewModel.savedMediaList(),
            listMeta: MediaList.Meta(artwork: rows.first?.coverURL, title: "Saved"),
            showSave: false
        )
    }

    func trackRow(_ row: Row, isLast: Bool) -> some View {
        TrackListRow(
            artwork: .placeholder(row.coverURL, name: row.title),
            title: row.title,
            subtitle: row.artist.flatMap { $0.isEmpty ? nil : "@\($0)" },
            activity: viewModel.mediaActivity(MediaID(row.id)),
            showsSeparator: !isLast,
            onTap: {
                searchFocused = false
                if let track = viewModel.savedTracks.first(where: { $0.trackId == row.id }) { viewModel.play(track) }
            }
        ) {
            Button {
                searchFocused = false
                if let track = viewModel.savedTracks.first(where: { $0.trackId == row.id }) { selectedTrack = track }
            } label: {
                LucideIcon(.ellipsis, .xl)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    func inlineState(icon: LucideIcon.Name, title: String, subtitle: String?) -> some View {
        VStack(spacing: 9) {
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appHeadline).foregroundStyle(.white)
            if let subtitle {
                Text(subtitle).font(.appFootnote).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 40)
    }
}

// MARK: - Search

private extension LibraryScreen {
    /// A query is typed — the page swaps to matching saved tracks.
    var isSearching: Bool {
        showSearchField && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Saved tracks matching the query (title or artist), all rows when empty.
    var searchMatches: [Row] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.artist?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Inline results — the same saved-track rows (play on tap, "…" options),
    /// just filtered. Quiet "No matches" while typing past the last hit.
    var searchResults: some View {
        LazyVStack(spacing: 0) {
            if searchMatches.isEmpty {
                Text("No matches")
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                ForEach(Array(searchMatches.enumerated()), id: \.element.id) { index, row in
                    trackRow(row, isLast: index == searchMatches.count - 1)
                }
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    LibraryScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
