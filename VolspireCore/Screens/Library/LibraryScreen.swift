 //
//  LibraryScreen.swift
//  Volspire
//
//  Your stuff in one place: a Workspace folder rail up top + your Saved tracks
//  below. Both are visible at a glance — no toggle — so each is always reachable.
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
    @State private var workspaceVM = WorkspaceScreenViewModel()
    @State private var playlistsVM = PlaylistsViewModel()
    @State private var selectedTrack: ApiUserLike? = nil
    @State private var addToPlaylistTrack: ApiUserLike? = nil
    @State private var showSearch = false
    /// Flips true once all three sections' first load resolves — until then the
    /// whole page shows one skeleton, then the real content cascades in together
    /// (mirrors the Marketplace skeleton → grid pattern).
    @State private var didLoad = false
    @State private var contentAppeared = false

    /// Bottom inset so the last rows clear the tab bar + (when present) the
    /// mini-player docked above it — same formula as Search / Messages /
    /// MediaCollection so every scrolling tab bottoms out consistently.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

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

    /// True while the workspace rail should still show its skeleton.
    private var workspaceLoading: Bool {
        if case .loading = workspaceVM.loadingState { return workspaceVM.folders.isEmpty }
        return false
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
            && workspaceVM.folders.isEmpty && playlistsVM.playlists.isEmpty
    }

    /// Retry every section (mirrors the pull-to-refresh).
    private func reloadAll() {
        Task {
            async let a: () = viewModel.refresh(currentUserId: dependencies.authManager.currentUserId)
            async let b: () = workspaceVM.refresh()
            async let c: () = playlistsVM.load()
            _ = await (a, b, c)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1) // keep the header's bottom shadow above the scrolling content
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
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            // First section fades in place (anchored) while the rest
                            // cascade up — matches Profile's hero-then-cascade feel.
                            workspaceSection.entranceReveal(contentAppeared, index: 0, distance: 0)
                            playlistsSection.entranceReveal(contentAppeared, index: 1)
                            savedSection.entranceReveal(contentAppeared, index: 2)
                        }
                        .transition(.opacity)
                        .onAppear { contentAppeared = true }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, bottomInset)
                .animation(.easeInOut(duration: 0.35), value: didLoad)
                .animation(.easeInOut(duration: 0.35), value: showLibraryError)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                async let a: () = viewModel.refresh(currentUserId: dependencies.authManager.currentUserId)
                async let b: () = workspaceVM.refresh()
                async let c: () = playlistsVM.load()
                _ = await (a, b, c)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationBarHidden(true)
        .gradientBackground()
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
            // Load all three sections concurrently so they resolve together
            // instead of popping in one after another.
            async let a: () = viewModel.load(currentUserId: dependencies.authManager.currentUserId)
            async let b: () = workspaceVM.loadFolders()
            async let c: () = playlistsVM.load()
            _ = await (a, b, c)
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
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .sheetBackground()
        }
        .sheet(item: $addToPlaylistTrack) { track in
            AddToPlaylistSheet(trackId: track.trackId)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .sheetBackground()
        }
        .sheet(isPresented: $showSearch) { searchSheet }
        .sheet(isPresented: $workspaceVM.showCreateFolder) { createSheet }
        .sheet(item: $workspaceVM.editingFolder) { _ in editSheet }
        .sheet(isPresented: $playlistsVM.showCreate) { playlistCreateSheet }
    }
}

// MARK: - Header

private extension LibraryScreen {
    var header: some View {
        ScreenHeader("Library") {
            HeaderIconButton(icon: .search) { showSearch = true }
        }
    }

    /// A consistent, modern section header: a bold title with an optional
    /// "See all" action on the right.
    func sectionHead(_ title: String, seeAll: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center) {
            Text(title).font(.appTitle3Bold).foregroundStyle(.white)
            Spacer(minLength: 0)
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 2) {
                        Text("See all").font(.appFootnoteMedium)
                        LucideIcon(.chevronRight, .xs)
                    }
                    .foregroundStyle(Color.vText2)
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
            skeletonSection(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { ForEach(0 ..< 3, id: \.self) { _ in folderSkeleton } }
                        .padding(.horizontal, ViewConst.screenPaddings)
                }
                .scrollDisabled(true)
            }
            skeletonSection(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) { ForEach(0 ..< 3, id: \.self) { _ in playlistSkeleton } }
                        .padding(.horizontal, ViewConst.screenPaddings)
                }
                .scrollDisabled(true)
            }
            skeletonSection(spacing: 10) {
                savedSkeletonRows
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

    var savedSkeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 6, id: \.self) { _ in
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)).frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Color.white.opacity(0.06)).frame(width: 160, height: 13)
                        Capsule().fill(Color.white.opacity(0.06)).frame(width: 90, height: 11)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.vertical, 9)
            }
        }
    }
}

// MARK: - Workspace section (horizontal folder rail)

private extension LibraryScreen {
    var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHead("Recent Activity") { router.navigateToWorkspace() }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if workspaceLoading {
                        ForEach(0 ..< 2, id: \.self) { _ in folderSkeleton }
                            .transition(.opacity)
                    } else if workspaceVM.folders.isEmpty {
                        emptyFolderCard
                            .transition(.opacity)
                    } else {
                        ForEach(workspaceVM.folders) { folderCard($0) }
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .animation(.easeInOut(duration: 0.3), value: workspaceLoading)
                // One shimmer sweep across the whole rail while loading (matches
                // the saved list + the rest of the app), not per-card.
                .shimmering(active: workspaceLoading)
            }
        }
    }

    func folderCard(_ folder: ApiUserFolder) -> some View {
        Button {
            router.navigateToFolder(folderId: folder.folderId, folderName: folder.name)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    LucideIcon(.folder, .lg)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer(minLength: 0)
                    FolderRolePill(role: folder.role)
                }

                Spacer(minLength: 0)

                Text(folder.name)
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                Text(workspaceVM.relativeTime(from: folder.createdAt))
                    .font(.appCaption2)
                    .foregroundStyle(Color.vText3)
            }
            .padding(14)
            .frame(width: 168, height: 132, alignment: .topLeading)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(LibraryPress())
        .contextMenu {
            if folder.role == "owner" {
                Button { workspaceVM.startEditing(folder) } label: { Label("Edit folder", systemImage: "pencil") }
            }
        }
    }

    var emptyFolderCard: some View {
        Button { workspaceVM.showCreateFolder = true } label: {
            VStack(spacing: 9) {
                LucideIcon(.plus, .lg).foregroundStyle(Color.vText2)
                Text("Create a folder").font(.appFootnoteMedium).foregroundStyle(Color.vText2)
            }
            .frame(width: 168, height: 132)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            )
        }
        .buttonStyle(LibraryPress())
    }

    var folderSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07))
                .frame(width: 44, height: 44)
            Spacer(minLength: 0)
            Capsule().fill(Color.white.opacity(0.07)).frame(width: 96, height: 13)
            Spacer(minLength: 4).frame(maxHeight: 12)
            Capsule().fill(Color.white.opacity(0.07)).frame(width: 52, height: 9)
        }
        .padding(14)
        .frame(width: 168, height: 132, alignment: .topLeading)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Playlists section

private extension LibraryScreen {
    var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHead("Playlists", seeAll: playlistsVM.playlists.isEmpty ? nil : { router.navigateToPlaylists() })

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    if playlistsLoading {
                        ForEach(0 ..< 2, id: \.self) { _ in playlistSkeleton }
                            .transition(.opacity)
                    } else if playlistsVM.playlists.isEmpty {
                        emptyPlaylistCard
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
        }
    }

    /// Empty-state card for the Playlists rail — a dashed "Create a playlist" tile
    /// (mirrors the Workspace `emptyFolderCard`) so users can make one from here.
    var emptyPlaylistCard: some View {
        Button { playlistsVM.showCreate = true } label: {
            VStack(spacing: 9) {
                LucideIcon(.plus, .lg).foregroundStyle(Color.vText2)
                Text("Create a playlist").font(.appFootnoteMedium).foregroundStyle(Color.vText2)
            }
            .frame(width: 158, height: 158)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            )
        }
        .buttonStyle(LibraryPress())
    }

    var playlistSkeleton: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 158, height: 158)
            Capsule().fill(Color.white.opacity(0.06)).frame(width: 110, height: 12)
            Capsule().fill(Color.white.opacity(0.06)).frame(width: 64, height: 10)
        }
        .frame(width: 158, alignment: .leading)
    }

    func playlistCard(_ playlist: ApiPlaylist) -> some View {
        Button {
            router.navigateToPlaylist(playlistId: playlist.playlistId, title: playlist.title)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ArtworkView(playlistsVM.cover(playlist.coverUrl).map { .webImage($0) } ?? .placeholder(name: playlist.title), cornerRadius: 16)
                    .frame(width: 158, height: 158)

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title).font(.appSubheadlineSemibold).foregroundStyle(.white).lineLimit(1)
                    Text("\(playlist.trackCount ?? 0) tracks").font(.appCaption).foregroundStyle(Color.vText2).lineLimit(1)
                }
                .frame(width: 158, alignment: .leading)
            }
            .frame(width: 158)
            .contentShape(.rect)
        }
        .buttonStyle(LibraryPress())
    }

    var playlistCreateSheet: some View {
        PlaylistFormSheet(
            icon: .listMusic,
            title: "New Playlist",
            subtitle: "Give it a cover, name, and description",
            name: $playlistsVM.newTitle,
            description: $playlistsVM.newDescription,
            coverData: $playlistsVM.newCoverData,
            savedCoverURL: nil,
            actionTitle: "Create",
            busy: playlistsVM.isCreating,
            onSubmit: { await playlistsVM.create() }
        )
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
            VStack(spacing: 0) {
                ForEach(0 ..< 5, id: \.self) { _ in
                    HStack(spacing: 13) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(Color.white.opacity(0.06)).frame(width: 160, height: 13)
                            Capsule().fill(Color.white.opacity(0.06)).frame(width: 90, height: 11)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.vertical, 9)
                }
            }
            .skeletonPulse()
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
        let activity = viewModel.mediaActivity(MediaID(row.id))
        let isActive = activity != nil
        return HStack(spacing: 13) {
            ArtworkView(row.coverURL.map { .webImage($0) } ?? .placeholder(name: row.title), cornerRadius: 9)
                .frame(width: 50, height: 50)
                // Cover loads/re-decodes on its own schedule; without this the
                // section's entrance/loading animations catch that change and
                // slide the image in from the bottom, out of sync with its row.
                // Clearing the transaction animation lets it appear in place.
                .transaction { $0.animation = nil }
                .overlay {
                    if let activity {
                        ZStack {
                            Color.black.opacity(0.45)
                            MediaActivityIndicator(state: activity).foregroundStyle(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.appCalloutSemibold)
                    .foregroundStyle(isActive ? .white : .white.opacity(0.95))
                    .lineLimit(1)
                if let artist = row.artist, !artist.isEmpty {
                    Text("@\(artist)").font(.appFootnote).foregroundStyle(Color.vText2).lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                if let track = viewModel.savedTracks.first(where: { $0.trackId == row.id }) { selectedTrack = track }
            } label: {
                LucideIcon(.ellipsis, .xl)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 63)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if let track = viewModel.savedTracks.first(where: { $0.trackId == row.id }) { viewModel.play(track) }
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

// MARK: - Create / Edit folder sheets

private extension LibraryScreen {
    var createSheet: some View {
        FolderFormSheet(
            icon: .folder,
            title: "New Folder",
            subtitle: "Organize your tracks and files",
            name: $workspaceVM.newFolderName,
            description: $workspaceVM.newFolderDescription,
            actionTitle: "Create Folder",
            busy: workspaceVM.isCreatingFolder,
            onSubmit: { await workspaceVM.createFolder() }
        )
    }

    var editSheet: some View {
        FolderFormSheet(
            icon: .squarePen,
            title: "Edit Folder",
            subtitle: "Update its name or description",
            name: $workspaceVM.editFolderName,
            description: $workspaceVM.editFolderDescription,
            actionTitle: "Save Changes",
            busy: workspaceVM.isEditingFolder,
            onSubmit: { await workspaceVM.editFolder() }
        )
    }
}

// MARK: - Search

private extension LibraryScreen {
    var searchSheet: some View {
        LibrarySearchSheet(rows: rows.map { ($0.id, $0.title, $0.artist, $0.coverURL) }) { id in
            if let track = viewModel.savedTracks.first(where: { $0.trackId == id }) { viewModel.play(track) }
            showSearch = false
        }
    }
}

// MARK: - Library Search Sheet

private struct LibrarySearchSheet: View {
    typealias RowTuple = (id: String, title: String, artist: String?, cover: URL?)
    let rows: [RowTuple]
    let onPlay: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [RowTuple] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.artist?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    LucideIcon(.search, .md).foregroundStyle(.secondary)
                    TextField("Search saved tracks…", text: $query)
                        .font(.appBody)
                        .focused($focused)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                Button("Cancel") { dismiss() }.font(.appCalloutRegular)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.id) { row in
                        Button {
                            onPlay(row.id)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(row.cover.map { .webImage($0) } ?? .placeholder(name: row.title), cornerRadius: 8)
                                    .frame(width: 46, height: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).font(.appCallout).lineLimit(1)
                                    if let artist = row.artist {
                                        Text(artist).font(.appFootnote).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 7)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .presentationDetents([.large])
        .sheetBackground()
        .onAppear { focused = true }
    }
}

/// Gentle scale + dim press feedback for the Library's cards.
private struct LibraryPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
