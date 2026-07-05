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
import PhotosUI
import Services
import SharedUtilities
import SwiftUI

/// Actions offered by the playlist's "…" options sheet. Captured on tap and run
/// in the sheet's `onDismiss` so the follow-up sheet/dialog presents cleanly.
private enum PlaylistMenuAction { case edit, delete }

/// A picked image awaiting crop — drives the full-screen cropper presentation.
private struct CropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Subtle press highlight for the flat options-menu rows.
private struct OptionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
            )
    }
}

struct PlaylistDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies

    @State private var viewModel: PlaylistDetailViewModel
    @State private var showDeleteConfirm = false
    @State private var showOptions = false
    @State private var pendingAction: PlaylistMenuAction?
    let title: String

    init(playlistId: String, title: String) {
        self.title = title
        _viewModel = State(wrappedValue: PlaylistDetailViewModel(playlistId: playlistId))
    }

    private var displayTitle: String { viewModel.detail?.title ?? title }

    /// The owner-only "…" button handed to MediaCollectionScreen's trailing slot.
    private var optionsButton: some View {
        Button { showOptions = true } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        content
            .task(id: viewModel.playlistId) {
                viewModel.mediaState = dependencies.mediaState
                viewModel.player = dependencies.mediaPlayer
                viewModel.currentUserId = dependencies.authManager.currentUserId
                await viewModel.load()
            }
            .sheet(isPresented: $showOptions, onDismiss: runPendingAction) { optionsSheet }
            .sheet(isPresented: $viewModel.showEdit) { editSheet }
            .confirmationDialog("Delete this playlist?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { if await viewModel.deletePlaylist() { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
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

                VStack(spacing: 0) {
                    ForEach(0 ..< 8, id: \.self) { _ in
                        HStack(spacing: 13) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(bone)
                                .frame(width: 50, height: 50)
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule().fill(bone).frame(width: 160, height: 13)
                                Capsule().fill(bone).frame(width: 90, height: 11)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.top, ViewConst.safeAreaInsets.top + 18)
            .frame(maxWidth: .infinity)
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
    }

    private func placeholder(icon: LucideIcon.Name, title: String, subtitle: String?) -> some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appBodyLargeSemibold).foregroundStyle(.white)
            if let subtitle {
                Text(subtitle).font(.appFootnote).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .background(Color.vBase.ignoresSafeArea())
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
    var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: displayTitle, subtitle: footer) {
                showOptions = false
            } leading: {
                optionsCover
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            optionsList
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        .sheetBackground()
    }

    @ViewBuilder
    var optionsCover: some View {
        if let url = viewModel.cover(viewModel.detail?.coverUrl) {
            ArtworkView(.webImage(url), cornerRadius: 11)
        } else {
            ZStack {
                Color.vSurface
                LucideIcon(.listMusic, .md).foregroundStyle(Color.vText2)
            }
        }
    }

    var optionsList: some View {
        VStack(spacing: 2) {
            optionRow(icon: .squarePen, title: "Edit playlist") {
                pendingAction = .edit; showOptions = false
            }
            optionRow(icon: .trash2, title: "Delete playlist", tint: Color(red: 1, green: 0.37, blue: 0.37)) {
                pendingAction = .delete; showOptions = false
            }
        }
    }

    func optionRow(icon: LucideIcon.Name, title: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                LucideIcon(icon, .lg)
                    .foregroundStyle(tint)
                    .frame(width: 26, alignment: .center)
                Text(title)
                    .font(.appBodyLargeMedium)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(OptionRowStyle())
    }

    /// Runs the action chosen in the options sheet — fired from the sheet's
    /// `onDismiss`, so the follow-up sheet/dialog presents over a clean stack.
    func runPendingAction() {
        let action = pendingAction
        pendingAction = nil
        switch action {
        case .edit: viewModel.startEditing()
        case .delete: showDeleteConfirm = true
        case .none: break
        }
    }
}

// MARK: - Edit sheet (cover · name · description)

private extension PlaylistDetailScreen {
    var editSheet: some View {
        PlaylistFormSheet(
            icon: .squarePen,
            title: "Edit Playlist",
            subtitle: "Update its cover, name, and description",
            name: $viewModel.editTitle,
            description: $viewModel.editDescription,
            coverData: $viewModel.pickedCoverData,
            savedCoverURL: viewModel.cover(viewModel.detail?.coverUrl),
            actionTitle: "Save Changes",
            busy: viewModel.isSaving,
            onSubmit: { await viewModel.saveEdit() }
        )
    }
}

/// Tappable 104×104 cover preview with a camera badge — shows the freshly
/// picked image, else the saved cover, else a neutral placeholder. Takes plain
/// values so it can be built inside PhotosPicker's `@Sendable` label closure.
private struct EditCoverPreview: View {
    let pickedData: Data?
    let savedURL: URL?

    var body: some View {
        Group {
            if let data = pickedData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let url = savedURL {
                ArtworkView(.webImage(url), cornerRadius: 18)
            } else {
                ZStack {
                    Color.white.opacity(0.07)
                    LucideIcon(.listMusic, .xxl).foregroundStyle(.white.opacity(0.55))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            .white.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                        )
                )
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.system(size: 12))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 2))
                .offset(x: 5, y: 5)
        }
    }
}

// MARK: - Shared playlist form sheet

/// Create/edit-playlist form — `SheetHeader` + cover picker (with cropper) + name
/// + description, themed like the folder/collab sheets. Used by the Library and
/// Playlists tabs (New Playlist) and the playlist detail (Edit Playlist).
struct PlaylistFormSheet: View {
    var icon: LucideIcon.Name = .listMusic
    let title: String
    let subtitle: String
    @Binding var name: String
    @Binding var description: String
    @Binding var coverData: Data?
    /// Existing cover (edit) shown when no new image has been picked.
    var savedCoverURL: URL? = nil
    let actionTitle: String
    let busy: Bool
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var coverItem: PhotosPickerItem?
    @State private var cropTarget: CropTarget?

    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // Hoisted: the PhotosPicker label closure is `@Sendable`, so it can't read
        // the main-actor `coverData` binding directly — capture plain values first.
        let pickedCover = coverData
        let savedCover = savedCoverURL
        return VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: icon, title: title, subtitle: subtitle) { dismiss() }

            VStack(spacing: 16) {
                PhotosPicker(selection: $coverItem, matching: .images) {
                    EditCoverPreview(pickedData: pickedCover, savedURL: savedCover)
                }
                .buttonStyle(.plain)

                VStack(spacing: 12) {
                    field(prompt: "Playlist name", text: $name)
                    field(prompt: "Description (optional)", text: $description)
                }

                Spacer(minLength: 0)

                Button { Task { await onSubmit() } } label: {
                    Group {
                        if busy { ProgressView().tint(.black) }
                        else { Text(actionTitle).font(.appHeadline).foregroundStyle(.black) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(valid && !busy ? Color.white : Color.white.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!valid || busy)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(452)])
        .presentationDragIndicator(.visible)
        .sheetBackground()
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    cropTarget = CropTarget(image: ui.normalizedUp())
                }
            }
        }
        .fullScreenCover(item: $cropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in coverData = data; cropTarget = nil },
                onCancel: { cropTarget = nil }
            )
        }
    }

    private func field(prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundColor(Color.vText3))
            .font(.appBody)
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vBorder))
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
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
    }
}
