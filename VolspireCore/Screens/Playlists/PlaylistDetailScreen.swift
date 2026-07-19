//
//  PlaylistDetailScreen.swift
//  Volspire
//
//  A playlist reuses the Home "See all" collection screen (MediaCollectionScreen)
//  for its cover-tinted hero + track list. This thin wrapper loads the playlist,
//  hands its tracks + cover to that screen, and — only when you own the playlist —
//  layers a "…" menu (edit/cover, share, privacy, delete) onto its nav bar.
//

import DesignSystem
import MediaLibrary
import Services
import SharedUtilities
import SwiftUI

struct PlaylistDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies

    @State private var viewModel: PlaylistDetailViewModel
    @State private var showDeleteConfirm = false
    @State private var showOptions = false
    let title: String

    init(playlistId: String, title: String) {
        self.title = title
        _viewModel = State(wrappedValue: PlaylistDetailViewModel(playlistId: playlistId))
    }

    private var displayTitle: String { viewModel.detail?.title ?? title }

    /// The owner-only "…" button handed to MediaCollectionScreen's trailing slot.
    private var optionsButton: some View {
        Button { showOptions = true } label: {
            LucideIcon(.ellipsis, size: ViewConst.headerIconSize)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        content
            .task(id: viewModel.playlistId) {
                viewModel.mediaState = dependencies.mediaState
                viewModel.currentUserId = dependencies.authManager.currentUserId
                await viewModel.load()
            }
            .sheet(isPresented: $showOptions) { optionsSheet }
            .sheet(isPresented: $viewModel.showEdit) { editSheet }
            .destructiveConfirm("Delete this playlist?", isPresented: $showDeleteConfirm) {
                Task { if await viewModel.deletePlaylist() { dismiss() } }
            }
    }

    /// Reuses MediaCollectionScreen (the Home "See all" screen) for the hero + list;
    /// the owner-only "…" menu is layered on via an extra toolbar item.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loaded:
            MediaCollectionScreen(
                items: viewModel.mediaItems,
                listMeta: MediaList.Meta(artwork: viewModel.cover(viewModel.detail?.coverUrl), title: displayTitle, subtitle: viewModel.detail?.description),
                trailingToolbar: viewModel.isOwner ? AnyView(optionsButton) : nil,
                currentPlaylistId: viewModel.playlistId,
                onRemoveFromPlaylist: viewModel.isOwner ? { media in await viewModel.removeTrack(trackId: media.id.value) } : nil
            )
            // Rebuild (refresh title/cover + re-extract palette) after an edit or a
            // track removal — the track count keys a fresh list.
            .id("\(viewModel.detail?.updatedAt ?? "")-\(viewModel.tracks.count)")
        case .error:
            LoadErrorView(title: "Couldn't load playlist") { Task { await viewModel.load() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.vBase.ignoresSafeArea())
                .immersiveLoadingChrome { dismiss() }
        default:
            collectionSkeleton
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.vBase.ignoresSafeArea())
                .immersiveLoadingChrome { dismiss() }
        }
    }

    /// Shimmering stand-in for the loaded `MediaCollectionScreen`: centred hero
    /// artwork + title + play/shuffle pills, then track-row bones.
    private var collectionSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return ScrollView {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(bone)
                    .frame(width: 168, height: 168)
                VStack(spacing: 8) {
                    Capsule().fill(bone).frame(width: 180, height: 22)
                    Capsule().fill(bone).frame(width: 120, height: 12)
                }
                HStack(spacing: 12) {
                    Capsule().fill(bone).frame(height: 46).frame(maxWidth: .infinity)
                    Capsule().fill(bone).frame(height: 46).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 4)

                SkeletonRows(count: 8, horizontalPadding: 14, boneOpacity: 0.08, shimmers: false)
                    .padding(.top, 6)
            }
            .padding(.top, ViewConst.safeAreaInsets.top + 18)
            .frame(maxWidth: .infinity)
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
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
                .init(icon: .trash2, title: "Delete playlist", isDestructive: true) {
                    showDeleteConfirm = true
                },
            ]
        )
        // Detents come from TrackOptionsSheet itself (sized to its rows).
        .sheetBackground()
    }
}

// MARK: - Edit sheet (cover · name · description)

private extension PlaylistDetailScreen {
    var editSheet: some View {
        ItemFormSheet(
            icon: .squarePen,
            title: "Edit Playlist",
            subtitle: "Update its cover, name, and description",
            namePrompt: "Playlist name",
            name: $viewModel.editTitle,
            description: $viewModel.editDescription,
            cover: .init(data: $viewModel.pickedCoverData, savedURL: viewModel.cover(viewModel.detail?.coverUrl)),
            actionTitle: "Save Changes",
            busy: viewModel.isSaving,
            onSubmit: { await viewModel.saveEdit() }
        )
    }
}

// MARK: - Immersive loading chrome

private extension View {
    /// Dark chrome for a pushed screen's loading/error state. Matches the loaded
    /// `MediaCollectionScreen` exactly — a transparent nav bar with a system-placed
    /// back button — so the back chevron sits in the same top-left spot and doesn't
    /// jump (or double-inset) when loading finishes. Swipe-back stays working.
    func immersiveLoadingChrome(onBack: @escaping () -> Void) -> some View {
        ignoresSafeArea(edges: .top)
            .preferredColorScheme(.dark)
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
