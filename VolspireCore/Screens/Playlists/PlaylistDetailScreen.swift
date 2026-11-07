//
//  PlaylistDetailScreen.swift
//  Volspire
//
//  A playlist reuses MediaCollectionScreen for its track list, with the
//  playlist header (big cover, title, @owner, Private). This thin wrapper
//  loads the playlist and — only when you own it — wires the header's
//  cover-edit, "Add tracks" picker and "…" menu (edit, delete).
//

import DesignSystem
import MediaLibrary
import Services
import SharedUtilities
import SwiftUI

struct PlaylistDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SocialStore.self) private var socialStore

    @State private var viewModel: PlaylistDetailViewModel
    @State private var showOptions = false
    @State private var showAddTracks = false
    let title: String

    init(playlistId: String, title: String) {
        self.title = title
        _viewModel = State(wrappedValue: PlaylistDetailViewModel(playlistId: playlistId))
    }

    private var displayTitle: String { viewModel.detail?.title ?? seed?.title ?? title }

    /// The playlist as the Library already knows it (title, cover,
    /// description, visibility) — renders the page's real layout on the first
    /// frame while `get_playlist` is in flight. Library only lists your own
    /// playlists, so a seed also means you own it.
    private var seed: ApiPlaylist? {
        libraryStore.playlists.first { $0.playlistId.caseInsensitiveCompare(viewModel.playlistId) == .orderedSame }
    }

    private var isLoaded: Bool { viewModel.detail != nil }
    private var isOwner: Bool { isLoaded ? viewModel.isOwner : seed != nil }

    private var listMeta: MediaList.Meta {
        MediaList.Meta(
            artwork: viewModel.cover(viewModel.detail?.coverUrl ?? seed?.coverUrl),
            title: displayTitle,
            subtitle: isLoaded ? viewModel.detail?.description : seed?.description
        )
    }

    private var header: PlaylistHeaderInfo {
        let owner = isOwner
        let me = seed != nil ? socialStore.myProfile : nil
        return PlaylistHeaderInfo(
            ownerUsername: viewModel.detail?.ownerUsername ?? me?.username,
            ownerId: viewModel.detail?.ownerId ?? me?.userId,
            isPrivate: (viewModel.detail?.visibility ?? seed?.visibility) == "private",
            isLoading: !isLoaded,
            onEditCover: owner ? { viewModel.startEditing() } : nil,
            onAddTracks: owner ? { showAddTracks = true } : nil,
            onMore: owner ? { showOptions = true } : nil
        )
    }

    var body: some View {
        content
            .task(id: viewModel.playlistId) {
                viewModel.mediaState = dependencies.mediaState
                viewModel.currentUserId = dependencies.authManager.currentUserId
                viewModel.library = libraryStore
                await viewModel.load()
            }
            .sheet(isPresented: $showOptions) { optionsSheet }
            // Full screen, laid out like Edit Track.
            .fullScreenCover(isPresented: $viewModel.showEdit) {
                EditPlaylistScreen(viewModel: viewModel)
            }
            .sheet(isPresented: $showAddTracks) {
                AddTracksSheet(
                    playlistId: viewModel.playlistId,
                    existingIds: Set(viewModel.tracks.map(\.trackId))
                ) { Task { await viewModel.load() } }
            }
    }

    /// One layout from the first frame: while loading, the header is filled
    /// from the Library's copy and the rows are bones, so nothing pops in or
    /// shifts. Edits and removals update the page in place.
    @ViewBuilder
    private var content: some View {
        if case .error = viewModel.state, !isLoaded {
            LoadErrorView(title: "Couldn't load playlist") { Task { await viewModel.load() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.vBase.ignoresSafeArea())
                .immersiveLoadingChrome { dismiss() }
        } else {
            MediaCollectionScreen(
                items: viewModel.mediaItems,
                listMeta: listMeta,
                currentPlaylistId: viewModel.playlistId,
                onRemoveFromPlaylist: isOwner ? { media in await viewModel.removeTrack(trackId: media.id.value) } : nil,
                playlistHeader: header,
                onRefresh: { await viewModel.load() }
            )
        }
    }

    private var footer: String {
        let n = viewModel.tracks.count
        let tracks = "\(n) track\(n == 1 ? "" : "s")"
        if let owner = viewModel.detail?.ownerUsername, !owner.isEmpty {
            return "@\(owner) · \(tracks)"
        }
        return tracks
    }
}

// MARK: - Options sheet (slide-up actions)

private extension PlaylistDetailScreen {
    /// The playlist "…" menu — built from the shared `TrackOptionsSheet` so it's
    /// pixel-identical to the track options sheet (same header, rows, and metrics).
    var optionsSheet: some View {
        TrackOptionsSheet(
            artwork: .placeholder(viewModel.cover(viewModel.detail?.coverUrl), name: displayTitle),
            title: displayTitle,
            meta: footer,
            actions: [
                .init(icon: .squarePen, title: "Edit playlist") {
                    viewModel.startEditing()
                },
                .init(
                    icon: .trash2, title: "Delete playlist", isDestructive: true,
                    confirm: DestructiveConfirm(
                        title: "Delete this playlist?",
                        message: "The tracks in it stay where they are."
                    ) {
                        dependencies.contentActions.deletePlaylist(id: viewModel.playlistId)
                        dismiss()
                    }
                ),
            ]
        )
        // Detents come from TrackOptionsSheet itself (sized to its rows).
        .sheetBackground()
    }
}

// MARK: - Edit playlist

/// Full-screen playlist edit (the shared Edit Track layout).
struct EditPlaylistScreen: View {
    let viewModel: PlaylistDetailViewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        EditDetailsScreen(
            title: "Edit Playlist",
            subtitle: "Update cover, name, and details",
            cover: .init(data: $viewModel.pickedCoverData,
                         savedURL: viewModel.cover(viewModel.detail?.coverUrl),
                         caption: "A square image, shown everywhere your playlist appears."),
            namePrompt: "Playlist name",
            name: $viewModel.editTitle,
            description: $viewModel.editDescription,
            hasChanges: viewModel.hasEditChanges,
            busy: viewModel.isSaving,
            error: viewModel.editError,
            onSave: { await viewModel.saveEdit() }
        )
        .onAppear { viewModel.editError = nil }
    }
}

// MARK: - Immersive loading chrome

/// Shared by the playlist and release pages.
extension View {
    /// Chrome for the error state: a transparent nav bar with the back button
    /// in the same top-left spot as the loaded page's. Swipe-back stays working.
    func immersiveLoadingChrome(onBack: @escaping () -> Void) -> some View {
        ignoresSafeArea(edges: .top)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .enableSwipeBack()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BackButton(action: onBack)
                }
            }
    }
}
