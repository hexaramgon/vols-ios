//
//  ReleaseDetailScreen.swift
//  Volspire
//
//  A release (an artist's grouped release) reuses MediaCollectionScreen with
//  the playlist header — big cover, title, @owner, Private — exactly like a
//  playlist page. Only the owner gets the cover edit, "Add tracks" (from
//  their own uploads) and the "…" menu (edit, reorder, public/private, delete).
//  Everything goes through the release RPCs via LibraryStore, so the profile
//  rail updates with every change.
//

import DesignSystem
import MediaLibrary
import Observation
import Services
import SharedUtilities
import SwiftUI

// MARK: - View model

@Observable @MainActor
final class ReleaseDetailViewModel {
    var detail: ApiReleaseDetail?
    var state: LoadState = .loading

    var showEdit = false
    var editTitle = ""
    var editDescription = ""
    var editVisibility = "public"
    var pickedCoverData: Data?
    var isSaving = false
    var actionError: String?

    let releaseId: String
    var currentUserId: String?
    weak var mediaState: MediaState?
    weak var library: LibraryStore?

    private let service: SupabaseService
    private let storage: StorageService

    init(releaseId: String, service: SupabaseService = SupabaseService(), storage: StorageService = StorageService()) {
        self.releaseId = releaseId
        self.service = service
        self.storage = storage
    }

    /// A just-saved track order, laid over `detail` until the next load
    /// returns it from the server (`get_release` orders by position).
    private var orderOverride: [String]?

    var tracks: [ApiReleaseTrack] {
        let base = detail?.tracks ?? []
        guard let order = orderOverride else { return base }
        let rank = Dictionary(order.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return base.sorted { (rank[$0.trackId.lowercased()] ?? .max) < (rank[$1.trackId.lowercased()] ?? .max) }
    }
    var mediaItems: [Media] { tracks.map { media(for: $0) } }

    var isOwner: Bool {
        guard let owner = detail?.ownerId, let me = currentUserId else { return false }
        return owner.caseInsensitiveCompare(me) == .orderedSame
    }

    func load() async {
        do {
            let detail = try await service.getRelease(releaseId: releaseId)
            self.detail = detail
            orderOverride = nil
            for track in detail.tracks ?? [] { await mediaState?.addTrack(media(for: track)) }
            state = .loaded
        } catch {
            debugLog("[ReleaseDetailVM] load: \(error)")
            state.fail(error, ifEmpty: detail == nil)
        }
    }

    func removeTrack(trackId: String) async {
        await run { try await $0.removeTrack(fromRelease: self.releaseId, trackId: trackId) }
        if actionError == nil { ToastCenter.shared.show("Removed from release") }
    }

    /// Optimistic: the page takes the new order now; a refusal puts the old
    /// one back + an error toast.
    func reorder(_ trackIds: [String]) async {
        guard let library else { return }
        let previous = orderOverride
        orderOverride = trackIds
        do {
            try await library.reorderRelease(releaseId: releaseId, trackIds: trackIds)
            ToastCenter.shared.show("Track order saved")
        } catch {
            debugLog("[ReleaseDetailVM] reorder: \(error)")
            orderOverride = previous
            ToastCenter.shared.show("Couldn't save the order — it's back.", style: .error)
        }
    }

    /// Returns whether the add went through (the sheet only checks it then).
    @discardableResult
    func addTracks(_ trackIds: [String]) async -> Bool {
        await run { try await $0.addTracks(toRelease: self.releaseId, trackIds: trackIds) }
    }

    func toggleVisibility() async {
        let next = detail?.visibility == "private" ? "public" : "private"
        await run {
            try await $0.updateRelease(releaseId: self.releaseId, title: nil, description: nil, visibility: next,
                                       releaseDate: nil, clearReleaseDate: false, coverData: nil)
        }
    }

    /// Save stays off until the title, description, privacy, or cover changed.
    var hasEditChanges: Bool {
        pickedCoverData != nil
            || editTitle.trimmingCharacters(in: .whitespacesAndNewlines) != (detail?.title ?? "")
            || editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            != (detail?.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            || editVisibility != (detail?.visibility == "private" ? "private" : "public")
    }

    func startEditing() {
        editTitle = detail?.title ?? ""
        editDescription = detail?.description ?? ""
        editVisibility = detail?.visibility == "private" ? "private" : "public"
        pickedCoverData = nil
        showEdit = true
    }

    func saveEdit() async {
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await run {
            try await $0.updateRelease(
                releaseId: self.releaseId, title: title,
                description: self.editDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                // Only send visibility when it actually changed.
                visibility: self.editVisibility == (self.detail?.visibility == "private" ? "private" : "public")
                    ? nil : self.editVisibility,
                releaseDate: nil, clearReleaseDate: false, coverData: self.pickedCoverData
            )
        }
        if actionError == nil {
            pickedCoverData = nil
            showEdit = false
        }
    }

    /// Runs a store mutation, then reloads this page; a failure surfaces as
    /// the page's error banner.
    @discardableResult
    private func run(_ mutation: (LibraryStore) async throws -> Void) async -> Bool {
        guard let library else { return false }
        actionError = nil
        do {
            try await mutation(library)
            await load()
            return true
        } catch {
            debugLog("[ReleaseDetailVM] mutation: \(error)")
            actionError = "Couldn't update the release. Please try again."
            return false
        }
    }

    func cover(_ path: String?) -> URL? {
        storage.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }

    private func media(for track: ApiReleaseTrack) -> Media {
        Media(
            id: MediaID(track.trackId),
            meta: MediaMeta(
                artwork: cover(track.coverUrl),
                title: track.title,
                artist: track.artistUsername,
                audioURL: storage.trackMediaURL(track.audioUrl)
            )
        )
    }
}

// MARK: - Screen

struct ReleaseDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(LibraryStore.self) private var libraryStore

    @State private var viewModel: ReleaseDetailViewModel
    @State private var showOptions = false
    @State private var showAddTracks = false
    @State private var showReorder = false
    let title: String

    init(releaseId: String, title: String) {
        self.title = title
        _viewModel = State(wrappedValue: ReleaseDetailViewModel(releaseId: releaseId))
    }

    /// The rail's copy of this release (own releases) — paints the header on
    /// the first frame while `get_release` is in flight.
    private var seed: ApiRelease? {
        libraryStore.myReleases.first { $0.releaseId.caseInsensitiveCompare(viewModel.releaseId) == .orderedSame }
    }

    private var isLoaded: Bool { viewModel.detail != nil }
    private var isOwner: Bool { isLoaded ? viewModel.isOwner : seed != nil }
    private var displayTitle: String { viewModel.detail?.title ?? seed?.title ?? title }

    private var listMeta: MediaList.Meta {
        MediaList.Meta(
            artwork: viewModel.cover(viewModel.detail?.coverUrl ?? seed?.coverUrl),
            title: displayTitle,
            subtitle: viewModel.detail?.description
        )
    }

    private var header: PlaylistHeaderInfo {
        let owner = isOwner
        return PlaylistHeaderInfo(
            ownerUsername: viewModel.detail?.ownerUsername,
            ownerId: viewModel.detail?.ownerId,
            isPrivate: (viewModel.detail?.visibility ?? seed?.visibility) == "private",
            isLoading: !isLoaded,
            onEditCover: owner ? { viewModel.startEditing() } : nil,
            onAddTracks: owner ? { showAddTracks = true } : nil,
            onMore: owner ? { showOptions = true } : nil,
            // An announced release with nothing in it yet.
            emptyTitle: owner ? nil : "Tracks coming soon"
        )
    }

    var body: some View {
        content
            .overlay(alignment: .bottom) {
                if let error = viewModel.actionError {
                    ErrorBanner(error)
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .task(id: viewModel.releaseId) {
                viewModel.mediaState = dependencies.mediaState
                viewModel.currentUserId = dependencies.authManager.currentUserId
                viewModel.library = libraryStore
                await viewModel.load()
            }
            .sheet(isPresented: $showOptions) { optionsSheet }
            // Full screen, like Edit Track.
            .fullScreenCover(isPresented: $viewModel.showEdit) {
                EditReleaseScreen(viewModel: viewModel)
            }
            .sheet(isPresented: $showReorder) {
                ReleaseReorderSheet(releaseTitle: displayTitle, tracks: viewModel.tracks) { ids in
                    Task { await viewModel.reorder(ids) }
                }
            }
            .sheet(isPresented: $showAddTracks) {
                ReleaseAddTracksSheet(existingIds: Set(viewModel.tracks.map { $0.trackId.lowercased() })) { ids in
                    await viewModel.addTracks(ids)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if case .error = viewModel.state, !isLoaded {
            LoadErrorView(title: "Couldn't load release") { Task { await viewModel.load() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.vBase.ignoresSafeArea())
                .immersiveLoadingChrome { dismiss() }
        } else {
            MediaCollectionScreen(
                items: viewModel.mediaItems,
                listMeta: listMeta,
                onRemoveFromPlaylist: isOwner ? { media in await viewModel.removeTrack(trackId: media.id.value) } : nil,
                removeLabel: "Remove from Release",
                playlistHeader: header,
                onRefresh: { await viewModel.load() }
            )
        }
    }

    /// "Release · 2026 · 8 tracks".
    private var meta: String {
        var parts = ["Release"]
        if let year = (viewModel.detail?.releaseDate ?? seed?.releaseDate)?.prefix(4), year.count == 4 {
            parts.append(String(year))
        }
        let n = viewModel.tracks.count
        parts.append("\(n) track\(n == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private var optionsSheet: some View {
        let isPrivate = viewModel.detail?.visibility == "private"
        // Reordering needs at least two tracks.
        let reorder: [TrackOptionsSheet.Action] = viewModel.tracks.count > 1
            ? [.init(icon: .arrowUpDown, title: "Reorder tracks") { showReorder = true }]
            : []
        return TrackOptionsSheet(
            artwork: .placeholder(viewModel.cover(viewModel.detail?.coverUrl), name: displayTitle),
            title: displayTitle,
            meta: meta,
            actions: [
                .init(icon: .squarePen, title: "Edit release") { viewModel.startEditing() },
            ] + reorder + [
                .init(icon: isPrivate ? .globe : .lock, title: isPrivate ? "Make public" : "Make private") {
                    Task { await viewModel.toggleVisibility() }
                },
                .init(
                    icon: .trash2, title: "Delete release", isDestructive: true,
                    confirm: DestructiveConfirm(
                        title: "Delete this release?",
                        message: "Its tracks stay on your profile."
                    ) {
                        dependencies.contentActions.deleteRelease(id: viewModel.releaseId)
                        dismiss()
                    }
                ),
            ]
        )
        .sheetBackground()
    }
}

// MARK: - Reorder tracks

/// The release "…" menu's "Reorder tracks": the tracks in a drag-to-reorder
/// list (always in edit mode, so every row shows its handle), saved as one
/// `reorder_release` call. Save closes the sheet at once; the page applies
/// the order optimistically.
struct ReleaseReorderSheet: View {
    let releaseTitle: String
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [ApiReleaseTrack]
    private let original: [String]
    private let storage = StorageService()

    init(releaseTitle: String, tracks: [ApiReleaseTrack], onSave: @escaping ([String]) -> Void) {
        self.releaseTitle = releaseTitle
        self.onSave = onSave
        _tracks = State(initialValue: tracks)
        original = tracks.map(\.trackId)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(icon: .arrowUpDown, title: "Reorder tracks", subtitle: releaseTitle) { dismiss() }

            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    row(index: index, track: track)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .onMove { tracks.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))

            CancelSendButtons(
                sendTitle: "Save",
                canSend: tracks.map(\.trackId) != original,
                isSending: false,
                onCancel: { dismiss() },
                onSend: {
                    onSave(tracks.map(\.trackId))
                    dismiss()
                }
            )
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .sheetBackground()
    }

    private func row(index: Int, track: ApiReleaseTrack) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.appCaption)
                .monospacedDigit()
                .foregroundStyle(Color.vText3)
                .frame(width: 18)
            ArtworkView(storage.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }.map { .webImage($0) } ?? .album,
                        cornerRadius: Radius.tile)
                .frame(width: 44, height: 44)
            Text(track.title).font(.appFont.trackTitle).foregroundStyle(Color.vText).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Add tracks (your own uploads)

/// The release page's "Add tracks": your uploads that aren't in it yet, each
/// with the pickers' add / added check. Stays open to add several.
struct ReleaseAddTracksSheet: View {
    /// Lowercased ids already in the release — hidden.
    let existingIds: Set<String>
    /// Returns whether the add succeeded.
    let onAdd: ([String]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var libraryStore
    @State private var addingId: String?
    @State private var addFailed = false
    @State private var addedIds: Set<String> = []

    private let storage = StorageService()

    private var candidates: [ApiProfileTrack] {
        libraryStore.uploadedTracks.filter { !existingIds.contains($0.id.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .listMusic, title: "Add tracks", subtitle: "Add from your uploads") { dismiss() }

            if addFailed {
                ErrorBanner("Couldn't add that track. Please try again.")
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
            }

            if candidates.isEmpty {
                switch libraryStore.loadState {
                case .idle, .loading:
                    ProgressView().tint(Color.vText2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error:
                    LoadErrorView(icon: .music, title: "Couldn't load your uploads") {
                        Task { await libraryStore.refresh() }
                    }
                case .loaded:
                    EmptyStateView(
                        icon: .music,
                        title: libraryStore.uploadedTracks.isEmpty ? "No uploads yet" : "Everything's already here",
                        message: libraryStore.uploadedTracks.isEmpty ? "Upload a track to add it to a release." : nil
                    )
                    .padding(.top, 36)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(candidates) { row($0) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .sheetBackground()
        .task { await libraryStore.loadIfNeeded() }
    }

    private func row(_ track: ApiProfileTrack) -> some View {
        let added = addedIds.contains(track.id)
        return Button {
            Task { await add(track) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(storage.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }.map { .webImage($0) } ?? .album,
                            cornerRadius: Radius.tile)
                    .frame(width: 44, height: 44)
                Text(track.title).font(.appFont.trackTitle).foregroundStyle(Color.vText).lineLimit(1)
                Spacer(minLength: 8)
                if addingId == track.id {
                    ProgressView().tint(Color.vText).controlSize(.small)
                } else {
                    AddedCheck(isOn: added)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
        .disabled(added || addingId != nil)
    }

    private func add(_ track: ApiProfileTrack) async {
        guard addingId == nil, !addedIds.contains(track.id) else { return }
        addingId = track.id
        addFailed = false
        if await onAdd([track.id]) {
            addedIds.insert(track.id)
            Haptics.impact(.soft)
        } else {
            addFailed = true
        }
        addingId = nil
    }
}

// MARK: - Edit release

/// Full-screen release edit (the shared Edit Track layout) plus Privacy.
struct EditReleaseScreen: View {
    let viewModel: ReleaseDetailViewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        EditDetailsScreen(
            title: "Edit Release",
            subtitle: "Update cover, title, and details",
            cover: .init(data: $viewModel.pickedCoverData,
                         savedURL: viewModel.cover(viewModel.detail?.coverUrl),
                         caption: "A square image, shown for the release and every track in it."),
            nameLabel: "Title",
            namePrompt: "Release title",
            nameLimit: CreateReleaseViewModel.titleLimit,
            name: $viewModel.editTitle,
            descriptionPrompt: "What's this release about?",
            descriptionLimit: InputLimits.releaseDescription,
            description: $viewModel.editDescription,
            hasChanges: viewModel.hasEditChanges,
            busy: viewModel.isSaving,
            error: viewModel.actionError,
            onSave: { await viewModel.saveEdit() }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                UploadSectionDivider("Privacy")
                UploadVisibilityPicker(
                    visibility: $viewModel.editVisibility,
                    publicHint: "Public: on your profile and anywhere releases show.",
                    privateHint: "Private: only you can see it. You can make it public later."
                )
            }
        }
    }
}
